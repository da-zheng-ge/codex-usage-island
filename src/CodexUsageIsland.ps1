param(
    [string]$CodexPath
)

function Resolve-CodexExecutable {
    $candidates = [System.Collections.Generic.List[string]]::new()

    try {
        Get-CimInstance Win32_Process -Filter "Name = 'codex.exe'" -ErrorAction Stop |
            Where-Object {
                $_.CommandLine -match '\bapp-server\b' -and
                $_.ExecutablePath -and
                $_.ExecutablePath -notmatch '\\WindowsApps\\'
            } |
            ForEach-Object { $candidates.Add($_.ExecutablePath) }
    }
    catch {}

    @(
        (Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\bin')
        (Join-Path $env:USERPROFILE '.vscode\extensions')
    ) | ForEach-Object {
        if (Test-Path -LiteralPath $_) {
            Get-ChildItem -LiteralPath $_ -Filter 'codex.exe' -File -Recurse -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTimeUtc -Descending |
                ForEach-Object { $candidates.Add($_.FullName) }
        }
    }

    $command = Get-Command 'codex.exe' -ErrorAction SilentlyContinue
    if ($command -and $command.Source) {
        $candidates.Add($command.Source)
    }

    foreach ($candidate in $candidates | Select-Object -Unique) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return $candidate
        }
    }

    throw 'Codex CLI was not found. Install or open Codex Desktop, then try again.'
}

if ([string]::IsNullOrWhiteSpace($CodexPath)) {
    $CodexPath = Resolve-CodexExecutable
}
elseif (-not (Test-Path -LiteralPath $CodexPath -PathType Leaf)) {
    throw "Codex executable not found: $CodexPath"
}

Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml
Add-Type -AssemblyName System.Web.Extensions

$source = @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Web.Script.Serialization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;

public sealed class CodexIslandWindow : Window
{
    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern bool IsIconic(IntPtr hWnd);

    private readonly string codexPath;
    private readonly JavaScriptSerializer json = new JavaScriptSerializer();
    private readonly Canvas canvas = new Canvas();
    private readonly Border shell = new Border();
    private readonly TextBlock summary = Text("5H --%   |   7D --%", 15, true, "#5EEAD4");
    private readonly TextBlock badgeText = Text("IDLE", 12, true, "#949EB2");
    private readonly Border badge = new Border();
    private readonly Border scanLine = new Border();
    private readonly Grid details = new Grid();
    private readonly TextBlock status = Text("Connecting...", 12, false, "#949EB2");
    private readonly LimitView five = new LimitView("5 \u5c0f\u65f6\u5269\u4f59");
    private readonly LimitView weekly = new LimitView("\u6bcf\u5468\u5269\u4f59");
    private readonly DispatcherTimer activityTimer = new DispatcherTimer();
    private readonly DispatcherTimer visibilityTimer = new DispatcherTimer();
    private Process server;
    private StreamWriter input;
    private int requestId = 2;
    private bool active;
    private bool wasActive;
    private bool expanded;
    private bool desiredVisible = true;
    private bool visibilityAnimating;
    private DateTime lastUsageRequest = DateTime.MinValue;
    private Storyboard activeStoryboard;

    private static readonly Brush BackgroundBrush = Brush("#11141B");
    private static readonly Brush CardBrush = Brush("#1B202B");
    private static readonly Brush AccentBrush = Brush("#5EEAD4");
    private static readonly Brush MutedBrush = Brush("#949EB2");

    public CodexIslandWindow(string path)
    {
        codexPath = path;
        Title = "Codex Usage Island";
        Width = 380;
        Height = 64;
        WindowStyle = WindowStyle.None;
        ResizeMode = ResizeMode.NoResize;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        Topmost = true;
        ShowInTaskbar = false;
        ShowActivated = false;
        SnapsToDevicePixels = false;
        UseLayoutRounding = false;

        shell.Background = BackgroundBrush;
        shell.CornerRadius = new CornerRadius(32);
        shell.ClipToBounds = true;
        shell.Child = canvas;
        Content = shell;

        var title = Text("Codex", 17, true, "#EEF2F8");
        Put(title, 22, 19, 82, 27);
        Put(summary, 105, 18, 184, 28);

        badge.Width = 62;
        badge.Height = 26;
        badge.CornerRadius = new CornerRadius(13);
        badge.Background = Brush("#2D323E");
        badge.Child = badgeText;
        badgeText.TextAlignment = TextAlignment.Center;
        badgeText.VerticalAlignment = VerticalAlignment.Center;
        Put(badge, 300, 19, 62, 26);

        scanLine.Width = 64;
        scanLine.Height = 3;
        scanLine.CornerRadius = new CornerRadius(2);
        scanLine.Background = AccentBrush;
        scanLine.Visibility = Visibility.Hidden;
        Put(scanLine, 18, 59, 64, 3);

        details.Visibility = Visibility.Collapsed;
        details.Opacity = 0;
        Put(details, 18, 72, 344, 205);
        BuildDetails();

        shell.MouseLeftButtonUp += delegate { ToggleExpanded(); };
        var menu = new ContextMenu();
        var toggleItem = new MenuItem { Header = "\u5c55\u5f00 / \u6536\u8d77" };
        toggleItem.Click += delegate { ToggleExpanded(); };
        var exitItem = new MenuItem { Header = "\u9000\u51fa" };
        exitItem.Click += delegate { Close(); };
        menu.Items.Add(toggleItem);
        menu.Items.Add(exitItem);
        ContextMenu = menu;

        activityTimer.Interval = TimeSpan.FromMilliseconds(750);
        activityTimer.Tick += delegate { CheckActivity(); };
        visibilityTimer.Interval = TimeSpan.FromMilliseconds(250);
        visibilityTimer.Tick += delegate { UpdateIslandVisibility(active || IsCodexWindowVisible()); };
        Loaded += delegate { PositionAtTop(); StartServer(); };
        Closed += delegate { StopServer(); };
    }

    private void BuildDetails()
    {
        details.RowDefinitions.Add(new RowDefinition { Height = new GridLength(78) });
        details.RowDefinitions.Add(new RowDefinition { Height = new GridLength(14) });
        details.RowDefinitions.Add(new RowDefinition { Height = new GridLength(78) });
        details.RowDefinitions.Add(new RowDefinition { Height = new GridLength(35) });
        five.Card.Background = CardBrush;
        weekly.Card.Background = CardBrush;
        Grid.SetRow(five.Card, 0);
        Grid.SetRow(weekly.Card, 2);
        Grid.SetRow(status, 3);
        status.VerticalAlignment = VerticalAlignment.Bottom;
        status.Margin = new Thickness(6, 0, 0, 0);
        details.Children.Add(five.Card);
        details.Children.Add(weekly.Card);
        details.Children.Add(status);
    }

    private void ToggleExpanded()
    {
        expanded = !expanded;
        if (expanded)
        {
            details.Visibility = Visibility.Visible;
            AnimateWindow(380, 290, true);
            AnimateOpacity(details, 1, 520);
            shell.CornerRadius = new CornerRadius(32);
        }
        else
        {
            AnimateOpacity(details, 0, 360);
            AnimateWindow(380, 64, false);
            shell.CornerRadius = new CornerRadius(32);
        }
    }

    private void AnimateWindow(double targetWidth, double targetHeight, bool opening)
    {
        Rect work = SystemParameters.WorkArea;
        double targetLeft = work.Left + (work.Width - targetWidth) / 2.0;
        var ease = new SineEase { EasingMode = EasingMode.EaseInOut };
        var duration = new Duration(TimeSpan.FromMilliseconds(500));
        var widthAnim = new DoubleAnimation(ActualWidth, targetWidth, duration) { EasingFunction = ease };
        var heightAnim = new DoubleAnimation(ActualHeight, targetHeight, duration) { EasingFunction = ease };
        var leftAnim = new DoubleAnimation(Left, targetLeft, duration) { EasingFunction = ease };
        heightAnim.Completed += delegate {
            BeginAnimation(WidthProperty, null);
            BeginAnimation(HeightProperty, null);
            BeginAnimation(LeftProperty, null);
            Width = targetWidth;
            Height = targetHeight;
            Left = targetLeft;
            if (!opening) details.Visibility = Visibility.Collapsed;
        };
        BeginAnimation(WidthProperty, widthAnim, HandoffBehavior.SnapshotAndReplace);
        BeginAnimation(HeightProperty, heightAnim, HandoffBehavior.SnapshotAndReplace);
        BeginAnimation(LeftProperty, leftAnim, HandoffBehavior.SnapshotAndReplace);
    }

    private static void AnimateOpacity(UIElement element, double target, int milliseconds)
    {
        var animation = new DoubleAnimation(target, TimeSpan.FromMilliseconds(milliseconds));
        element.BeginAnimation(OpacityProperty, animation);
    }

    private void PositionAtTop()
    {
        Rect work = SystemParameters.WorkArea;
        Left = work.Left + (work.Width - Width) / 2.0;
        Top = work.Top + 10;
    }

    private void StartServer()
    {
        try
        {
            var psi = new ProcessStartInfo(codexPath, "app-server --stdio") {
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardInput = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };
            server = new Process { StartInfo = psi, EnableRaisingEvents = true };
            server.OutputDataReceived += OnOutput;
            server.ErrorDataReceived += delegate { };
            server.Start();
            input = server.StandardInput;
            server.BeginOutputReadLine();
            server.BeginErrorReadLine();
            Send("{\"method\":\"initialize\",\"id\":0,\"params\":{\"clientInfo\":{\"name\":\"usage_island\",\"title\":\"Codex Usage Island\",\"version\":\"2.0.0\"}}}");
            Send("{\"method\":\"initialized\",\"params\":{}}");
            RequestUsage();
            activityTimer.Start();
            visibilityTimer.Start();
        }
        catch (Exception ex) { status.Text = "Start failed: " + ex.Message; }
    }

    private void RequestUsage()
    {
        if (server == null || server.HasExited) return;
        Send("{\"method\":\"account/rateLimits/read\",\"id\":" + requestId++ + ",\"params\":{}}");
        lastUsageRequest = DateTime.Now;
        status.Text = "\u6b63\u5728\u5237\u65b0...";
    }

    private void Send(string message) { input.WriteLine(message); input.Flush(); }

    private void OnOutput(object sender, DataReceivedEventArgs e)
    {
        if (String.IsNullOrWhiteSpace(e.Data)) return;
        try
        {
            var root = json.DeserializeObject(e.Data) as Dictionary<string, object>;
            if (root == null || !root.ContainsKey("result")) return;
            var result = root["result"] as Dictionary<string, object>;
            if (result == null || !result.ContainsKey("rateLimits")) return;
            var limits = result["rateLimits"] as Dictionary<string, object>;
            if (limits == null) return;
            Dispatcher.BeginInvoke((Action)(() => ApplyLimits(limits)));
        }
        catch { }
    }

    private void ApplyLimits(Dictionary<string, object> limits)
    {
        var primary = Dict(limits, "primary");
        var secondary = Dict(limits, "secondary");
        five.Apply(primary, active);
        weekly.Apply(secondary, active);
        summary.Text = "5H " + Remaining(primary) + "   |   7D " + Remaining(secondary);
        status.Text = active
            ? "\u5df2\u66f4\u65b0  " + DateTime.Now.ToString("HH:mm:ss") + "  |  \u6bcf 15 \u79d2\u5237\u65b0"
            : "\u5df2\u66f4\u65b0  " + DateTime.Now.ToString("HH:mm:ss") + "  |  \u7a7a\u95f2\u65f6\u6682\u505c";
    }

    private void CheckActivity()
    {
        active = IsCodexActive();
        UpdateIslandVisibility(active || IsCodexWindowVisible());
        if (active != wasActive) SetActiveVisual(active);
        if (active && (!wasActive || (DateTime.Now - lastUsageRequest).TotalSeconds >= 15)) RequestUsage();
        else status.Text = active ? "Codex \u5bf9\u8bdd\u4e2d  |  \u6bcf 15 \u79d2\u5237\u65b0" : "Codex \u7a7a\u95f2  |  \u5df2\u6682\u505c\u5237\u65b0";
        wasActive = active;
    }

    private void UpdateIslandVisibility(bool shouldShow)
    {
        desiredVisible = shouldShow;
        if (shouldShow)
        {
            if (!IsVisible)
            {
                double restingTop = SystemParameters.WorkArea.Top + 10;
                Opacity = 0;
                Top = restingTop - 12;
                Show();
                Left = SystemParameters.WorkArea.Left + (SystemParameters.WorkArea.Width - Width) / 2.0;
                Topmost = true;
                AnimateVisibility(true, restingTop);
            }
            else if (visibilityAnimating)
            {
                BeginAnimation(OpacityProperty, null);
                BeginAnimation(TopProperty, null);
                Opacity = 1;
                Top = SystemParameters.WorkArea.Top + 10;
                visibilityAnimating = false;
            }
        }
        else if (IsVisible && !visibilityAnimating)
        {
            AnimateVisibility(false, SystemParameters.WorkArea.Top + 10);
        }
    }

    private void AnimateVisibility(bool showing, double restingTop)
    {
        visibilityAnimating = true;
        var ease = new SineEase { EasingMode = EasingMode.EaseInOut };
        var duration = new Duration(TimeSpan.FromMilliseconds(220));
        var opacity = new DoubleAnimation(showing ? 0 : 1, showing ? 1 : 0, duration) { EasingFunction = ease };
        var top = new DoubleAnimation(showing ? restingTop - 12 : restingTop, showing ? restingTop : restingTop - 12, duration) { EasingFunction = ease };
        opacity.Completed += delegate {
            BeginAnimation(OpacityProperty, null);
            BeginAnimation(TopProperty, null);
            visibilityAnimating = false;
            Top = restingTop;
            Opacity = 1;
            if (!desiredVisible) Hide();
        };
        BeginAnimation(OpacityProperty, opacity, HandoffBehavior.SnapshotAndReplace);
        BeginAnimation(TopProperty, top, HandoffBehavior.SnapshotAndReplace);
    }

    private static bool IsCodexWindowVisible()
    {
        try
        {
            foreach (Process process in Process.GetProcessesByName("Codex"))
            {
                IntPtr handle = process.MainWindowHandle;
                if (handle != IntPtr.Zero && IsWindowVisible(handle) && !IsIconic(handle))
                    return true;
            }
        }
        catch { }
        return false;
    }

    private void SetActiveVisual(bool value)
    {
        badgeText.Text = value ? "ACTIVE" : "IDLE";
        if (!value)
        {
            if (activeStoryboard != null) activeStoryboard.Stop(this);
            badge.Opacity = 1;
            badge.Background = Brush("#2D323E");
            badgeText.Foreground = MutedBrush;
            scanLine.Visibility = Visibility.Hidden;
            return;
        }
        badge.Background = Brush("#214743");
        badgeText.Foreground = AccentBrush;
        scanLine.Visibility = Visibility.Visible;
        activeStoryboard = new Storyboard { RepeatBehavior = RepeatBehavior.Forever };
        var pulse = new DoubleAnimation(0.55, 1.0, TimeSpan.FromMilliseconds(650)) { AutoReverse = true };
        Storyboard.SetTarget(pulse, badge);
        Storyboard.SetTargetProperty(pulse, new PropertyPath(OpacityProperty));
        var travel = new DoubleAnimation(18, 298, TimeSpan.FromMilliseconds(1200));
        Storyboard.SetTarget(travel, scanLine);
        Storyboard.SetTargetProperty(travel, new PropertyPath("(Canvas.Left)"));
        activeStoryboard.Children.Add(pulse);
        activeStoryboard.Children.Add(travel);
        activeStoryboard.Begin(this, true);
    }

    private bool IsCodexActive()
    {
        try
        {
            string root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".codex", "sessions");
            if (!Directory.Exists(root)) return false;
            string[] paths = Directory.GetFiles(root, "*.jsonl", SearchOption.AllDirectories);
            Array.Sort(paths, delegate(string a, string b) { return File.GetLastWriteTimeUtc(b).CompareTo(File.GetLastWriteTimeUtc(a)); });
            for (int i = 0; i < Math.Min(paths.Length, 10); i++) if (LastTaskMarker(paths[i]) == "task_started") return true;
        }
        catch { }
        return false;
    }

    private string LastTaskMarker(string path)
    {
        try
        {
            const int maxBytes = 2 * 1024 * 1024;
            byte[] bytes;
            using (var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
            {
                int length = (int)Math.Min(stream.Length, maxBytes);
                bytes = new byte[length];
                stream.Seek(-length, SeekOrigin.End);
                stream.Read(bytes, 0, length);
            }
            string[] lines = System.Text.Encoding.UTF8.GetString(bytes).Split(new[] { '\n' }, StringSplitOptions.RemoveEmptyEntries);
            for (int i = lines.Length - 1; i >= 0; i--)
            {
                if (!lines[i].Contains("task_started") && !lines[i].Contains("task_complete")) continue;
                try
                {
                    var root = json.DeserializeObject(lines[i]) as Dictionary<string, object>;
                    if (root == null || Convert.ToString(root["type"]) != "event_msg") continue;
                    var payload = root["payload"] as Dictionary<string, object>;
                    string type = payload == null ? null : Convert.ToString(payload["type"]);
                    if (type == "task_started" || type == "task_complete") return type;
                }
                catch { }
            }
        }
        catch { }
        return null;
    }

    private void StopServer()
    {
        activityTimer.Stop();
        visibilityTimer.Stop();
        try { if (server != null && !server.HasExited) server.Kill(); } catch { }
    }

    private static Dictionary<string, object> Dict(Dictionary<string, object> source, string key)
    {
        object value;
        return source.TryGetValue(key, out value) ? value as Dictionary<string, object> : null;
    }

    private static string Remaining(Dictionary<string, object> window)
    {
        if (window == null || !window.ContainsKey("usedPercent")) return "N/A";
        return (100 - Math.Max(0, Math.Min(100, Convert.ToInt32(window["usedPercent"])))) + "%";
    }

    private static TextBlock Text(string value, double size, bool bold, string color)
    {
        return new TextBlock {
            Text = value,
            FontFamily = new FontFamily("Segoe UI"),
            FontSize = size,
            FontWeight = bold ? FontWeights.Bold : FontWeights.Normal,
            Foreground = Brush(color),
            VerticalAlignment = VerticalAlignment.Center
        };
    }

    private void Put(UIElement element, double left, double top, double width, double height)
    {
        Canvas.SetLeft(element, left);
        Canvas.SetTop(element, top);
        FrameworkElement frameworkElement = element as FrameworkElement;
        if (frameworkElement != null) { frameworkElement.Width = width; frameworkElement.Height = height; }
        canvas.Children.Add(element);
    }

    private static SolidColorBrush Brush(string hex)
    {
        var brush = new SolidColorBrush((Color)ColorConverter.ConvertFromString(hex));
        brush.Freeze();
        return brush;
    }

    private sealed class LimitView
    {
        public readonly Border Card = new Border { CornerRadius = new CornerRadius(12), Padding = new Thickness(14, 8, 14, 7) };
        private readonly TextBlock value = Text("--%", 18, true, "#5EEAD4");
        private readonly TextBlock reset = Text("\u7b49\u5f85\u6570\u636e", 11, false, "#949EB2");
        private readonly Border fill = new Border { Height = 9, CornerRadius = new CornerRadius(5), Background = AccentBrush, HorizontalAlignment = HorizontalAlignment.Left };

        public LimitView(string name)
        {
            var grid = new Grid();
            grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(29) });
            grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(15) });
            grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(18) });
            var header = new Grid();
            header.ColumnDefinitions.Add(new ColumnDefinition());
            header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(70) });
            var label = Text(name, 14, true, "#EEF2F8");
            value.TextAlignment = TextAlignment.Right;
            Grid.SetColumn(value, 1);
            header.Children.Add(label);
            header.Children.Add(value);
            var track = new Grid { Height = 9, Background = Brush("#323A4A"), ClipToBounds = true };
            track.Children.Add(fill);
            Grid.SetRow(track, 1);
            Grid.SetRow(reset, 2);
            grid.Children.Add(header);
            grid.Children.Add(track);
            grid.Children.Add(reset);
            Card.Child = grid;
        }

        public void Apply(Dictionary<string, object> window, bool active)
        {
            if (window == null) { value.Text = "N/A"; fill.Width = 0; return; }
            int used = Math.Max(0, Math.Min(100, Convert.ToInt32(window["usedPercent"])));
            int remaining = 100 - used;
            value.Text = remaining + "%";
            fill.Width = 316 * remaining / 100.0;
            Brush color = remaining <= 10 ? Brush("#F87171") : remaining <= 30 ? Brush("#FBBF24") : AccentBrush;
            value.Foreground = fill.Background = color;
            object raw;
            if (window.TryGetValue("resetsAt", out raw) && raw != null)
            {
                DateTime local = DateTimeOffset.FromUnixTimeSeconds(Convert.ToInt64(raw)).LocalDateTime;
                reset.Text = "\u5df2\u7528 " + used + "%  |  \u91cd\u7f6e " + local.ToString("MM-dd HH:mm");
            }
            else reset.Text = "\u5df2\u7528 " + used + "%";
        }
    }
}
'@

Add-Type -TypeDefinition $source -ReferencedAssemblies @(
    'PresentationCore',
    'PresentationFramework',
    'WindowsBase',
    'System.Xaml',
    'System.Web.Extensions'
)

$app = [System.Windows.Application]::new()
$app.ShutdownMode = [System.Windows.ShutdownMode]::OnMainWindowClose
$window = [CodexIslandWindow]::new($CodexPath)
$app.Run($window)
