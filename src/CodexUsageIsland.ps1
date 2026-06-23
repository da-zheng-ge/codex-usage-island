param(
    [string]$CodexPath
)

$createdNew = $false
$singleInstanceMutex = [System.Threading.Mutex]::new(
    $true,
    'Local\CodexUsageIsland.SingleInstance',
    [ref]$createdNew
)
$activationEventCreated = $false
$activationEvent = [System.Threading.EventWaitHandle]::new(
    $false,
    [System.Threading.EventResetMode]::AutoReset,
    'Local\CodexUsageIsland.Activate',
    [ref]$activationEventCreated
)

if (-not $createdNew) {
    $activationEvent.Set() | Out-Null
    $activationEvent.Dispose()
    $singleInstanceMutex.Dispose()
    exit 0
}

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
using System.Net;
using System.Runtime.InteropServices;
using System.Threading;
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
    private readonly MenuItem updateItem = new MenuItem();
    private readonly TextBlock updateHeaderText = new TextBlock();
    private readonly System.Windows.Shapes.Ellipse updateDot = new System.Windows.Shapes.Ellipse { Width = 8, Height = 8, Visibility = Visibility.Collapsed };
    private string currentVersion = "unknown";
    private string latestVersion = "checking";
    private bool updateAvailable;
    private readonly Canvas canvas = new Canvas();
    private readonly Border shell = new Border();
    private readonly TextBlock summary = Text("5H --%   |   7D --%", 15, true, "#5EEAD4");
    private readonly TextBlock badgeText = Text("IDLE", 12, true, "#949EB2");
    private readonly Border badge = new Border();
    private readonly Border scanLine = new Border();
    private readonly Grid details = new Grid();
    private readonly TextBlock status = Text("Connecting...", 12, false, "#949EB2");
    private readonly LimitView five = new LimitView("5 \u5c0f\u65f6\u5269\u4f59", false);
    private readonly LimitView weekly = new LimitView("\u6bcf\u5468\u5269\u4f59", true);
    private readonly DispatcherTimer activityTimer = new DispatcherTimer();
    private readonly DispatcherTimer visibilityTimer = new DispatcherTimer();
    private readonly EventWaitHandle activationEvent;
    private readonly string uninstallerPath;
    private Process server;
    private StreamWriter input;
    private int requestId = 2;
    private bool active;
    private bool wasActive;
    private bool expanded;
    private bool desiredVisible = true;
    private bool visibilityAnimating;
    private bool pointerDown;
    private bool dragging;
    private Point pointerStart;
    private Point windowStart;
    private double restingLeft;
    private double restingTop;
    private DateTime lastUsageRequest = DateTime.MinValue;
    private DateTime resetPollingTarget = DateTime.MinValue;
    private DateTime nextResetPoll = DateTime.MaxValue;
    private int resetPollsRemaining;
    private Storyboard activeStoryboard;

    private static readonly Brush BackgroundBrush = Brush("#11141B");
    private static readonly Brush CardBrush = Brush("#1B202B");
    private static readonly Brush AccentBrush = Brush("#5EEAD4");
    private static readonly Brush MutedBrush = Brush("#949EB2");

    public CodexIslandWindow(string path, string scriptPath, EventWaitHandle activation)
    {
        codexPath = path;
        activationEvent = activation;
        uninstallerPath = Path.Combine(Path.GetDirectoryName(scriptPath), "uninstall.ps1");
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

        shell.MouseLeftButtonDown += OnShellMouseLeftButtonDown;
        shell.MouseMove += OnShellMouseMove;
        shell.MouseLeftButtonUp += OnShellMouseLeftButtonUp;
        var menu = new ContextMenu();
        var refreshItem = new MenuItem { Header = "\u5237\u65b0\u989d\u5ea6" };
        refreshItem.Click += delegate { RequestUsage(); };
        updateItem.Header = BuildUpdateHeader();
        updateItem.Click += delegate { UpdateApp(); };
        var resetPositionItem = new MenuItem { Header = "\u91cd\u7f6e\u4f4d\u7f6e" };
        resetPositionItem.Click += delegate { PositionAtTop(); };
        var taskbarItem = new MenuItem { Header = "\u6536\u8fdb\u4efb\u52a1\u680f" };
        taskbarItem.Click += delegate { MinimizeToTaskbar(); };
        var githubItem = new MenuItem { Header = "GitHub" };
        githubItem.Click += delegate { OpenGitHub(); };
        var uninstallItem = new MenuItem { Header = "\u5378\u8f7d", IsEnabled = File.Exists(uninstallerPath) };
        uninstallItem.Click += delegate { Uninstall(); };
        var exitItem = new MenuItem { Header = "\u9000\u51fa" };
        exitItem.Click += delegate { Close(); };
        menu.Items.Add(refreshItem);
        menu.Items.Add(updateItem);
        menu.Items.Add(resetPositionItem);
        menu.Items.Add(taskbarItem);
        menu.Items.Add(githubItem);
        menu.Items.Add(new Separator());
        menu.Items.Add(uninstallItem);
        menu.Items.Add(exitItem);
        ContextMenu = menu;

        activityTimer.Interval = TimeSpan.FromMilliseconds(750);
        activityTimer.Tick += delegate { CheckActivity(); };
        visibilityTimer.Interval = TimeSpan.FromMilliseconds(250);
        visibilityTimer.Tick += delegate { CheckVisibility(); };
        Loaded += delegate { PositionAtTop(); StartServer(); CheckForUpdatesAsync(); };
        StateChanged += delegate { RestoreFromTaskbarIfNeeded(); };
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

    private void Uninstall()
    {
        MessageBoxResult result = MessageBox.Show(
            "\u786e\u5b9a\u8981\u5378\u8f7d Codex Usage Island \u5417\uff1f",
            "Codex Usage Island",
            MessageBoxButton.YesNo,
            MessageBoxImage.Warning
        );
        if (result != MessageBoxResult.Yes) return;

        var startInfo = new ProcessStartInfo {
            FileName = "powershell.exe",
            Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"" + uninstallerPath + "\"",
            UseShellExecute = false,
            CreateNoWindow = true
        };
        Process.Start(startInfo);
        Close();
    }

    private void OpenGitHub()
    {
        Process.Start(new ProcessStartInfo {
            FileName = "https://github.com/da-zheng-ge/codex-usage-island",
            UseShellExecute = true
        });
    }

    private void UpdateApp()
    {
        MessageBoxResult result = MessageBox.Show(
            "\u5c06\u4ece GitHub \u4e0b\u8f7d\u5e76\u5b89\u88c5\u6700\u65b0\u7248\u672c\uff0c\u662f\u5426\u7ee7\u7eed\uff1f",
            "Codex Usage Island",
            MessageBoxButton.YesNo,
            MessageBoxImage.Question
        );
        if (result != MessageBoxResult.Yes) return;

        status.Text = "\u6b63\u5728\u66f4\u65b0...";
        string script = @"
$ErrorActionPreference = 'Stop'
$work = Join-Path $env:TEMP ('codex-usage-island-update-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work -Force | Out-Null
$zip = Join-Path $work 'main.zip'
Invoke-WebRequest -Uri 'https://github.com/da-zheng-ge/codex-usage-island/archive/refs/heads/main.zip' -OutFile $zip -UseBasicParsing
Expand-Archive -LiteralPath $zip -DestinationPath $work -Force
$install = Join-Path $work 'codex-usage-island-main\install.ps1'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $install
";
        string encoded = Convert.ToBase64String(System.Text.Encoding.Unicode.GetBytes(script));
        var startInfo = new ProcessStartInfo {
            FileName = "powershell.exe",
            Arguments = "-NoProfile -ExecutionPolicy Bypass -EncodedCommand " + encoded,
            UseShellExecute = false,
            CreateNoWindow = true
        };
        Process.Start(startInfo);
        Close();
    }

    private void CheckForUpdatesAsync()
    {
        LoadCurrentVersion();
        UpdateVersionMenu();
        ThreadPool.QueueUserWorkItem(delegate {
            try
            {
                using (var client = new WebClient())
                {
                    client.Headers.Add("User-Agent", "CodexUsageIsland");
                    string response = client.DownloadString("https://api.github.com/repos/da-zheng-ge/codex-usage-island/releases/latest");
                    var root = json.DeserializeObject(response) as Dictionary<string, object>;
                    if (root == null || !root.ContainsKey("tag_name")) return;
                    string latest = Convert.ToString(root["tag_name"]);
                    if (string.IsNullOrWhiteSpace(latest)) return;
                    latestVersion = latest.Trim();
                    updateAvailable = IsNewerVersion(latestVersion, currentVersion);
                    Dispatcher.BeginInvoke((Action)(() => UpdateVersionMenu()));
                }
            }
            catch
            {
                latestVersion = "unknown";
                Dispatcher.BeginInvoke((Action)(() => UpdateVersionMenu()));
            }
        });
    }

    private void LoadCurrentVersion()
    {
        try
        {
            string versionPath = Path.Combine(Path.GetDirectoryName(uninstallerPath), ".version");
            if (File.Exists(versionPath))
            {
                string value = File.ReadAllText(versionPath).Trim();
                if (!string.IsNullOrWhiteSpace(value)) currentVersion = value;
            }
        }
        catch { }
    }

    private void UpdateVersionMenu()
    {
        updateHeaderText.Text = "\u66f4\u65b0  \u5f53\u524d " + ShortVersion(currentVersion) + " / \u6700\u65b0 " + ShortVersion(latestVersion);
        updateDot.Visibility = updateAvailable ? Visibility.Visible : Visibility.Collapsed;
    }

    private UIElement BuildUpdateHeader()
    {
        var grid = new Grid();
        updateHeaderText.VerticalAlignment = VerticalAlignment.Center;
        updateDot.Fill = Brush("#EF4444");
        updateDot.HorizontalAlignment = HorizontalAlignment.Left;
        updateDot.VerticalAlignment = VerticalAlignment.Top;
        updateDot.Margin = new Thickness(24, -2, 0, 0);
        grid.Children.Add(updateHeaderText);
        grid.Children.Add(updateDot);
        UpdateVersionMenu();
        return grid;
    }

    private static string ShortVersion(string value)
    {
        if (string.IsNullOrWhiteSpace(value)) return "unknown";
        value = value.Trim();
        if (value.Length > 7)
        {
            bool hexLike = true;
            for (int i = 0; i < value.Length; i++)
            {
                char c = value[i];
                if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')))
                {
                    hexLike = false;
                    break;
                }
            }
            if (hexLike) return value.Substring(0, 7);
        }
        return value;
    }

    private static bool IsNewerVersion(string latest, string current)
    {
        int[] latestParts = ParseVersion(latest);
        int[] currentParts = ParseVersion(current);
        if (latestParts == null || currentParts == null)
        {
            return current != "unknown" && !string.Equals(latest, current, StringComparison.OrdinalIgnoreCase);
        }

        for (int i = 0; i < 3; i++)
        {
            if (latestParts[i] > currentParts[i]) return true;
            if (latestParts[i] < currentParts[i]) return false;
        }
        return false;
    }

    private static int[] ParseVersion(string value)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        value = value.Trim();
        if (value.StartsWith("v", StringComparison.OrdinalIgnoreCase)) value = value.Substring(1);
        int suffix = value.IndexOfAny(new[] { '-', '+' });
        if (suffix >= 0) value = value.Substring(0, suffix);
        string[] tokens = value.Split('.');
        int[] parts = new[] { 0, 0, 0 };
        for (int i = 0; i < tokens.Length && i < 3; i++)
        {
            int parsed;
            if (!int.TryParse(tokens[i], out parsed)) return null;
            parts[i] = parsed;
        }
        return parts;
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

    private void OnShellMouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        BeginAnimation(OpacityProperty, null);
        BeginAnimation(TopProperty, null);
        Opacity = 1;
        visibilityAnimating = false;
        pointerDown = true;
        dragging = false;
        pointerStart = PointerScreenPosition(e);
        windowStart = new Point(Left, Top);
        shell.CaptureMouse();
        e.Handled = true;
    }

    private void OnShellMouseMove(object sender, MouseEventArgs e)
    {
        if (!pointerDown || e.LeftButton != MouseButtonState.Pressed) return;
        Point current = PointerScreenPosition(e);
        Vector delta = current - pointerStart;
        if (!dragging && Math.Abs(delta.X) < SystemParameters.MinimumHorizontalDragDistance &&
            Math.Abs(delta.Y) < SystemParameters.MinimumVerticalDragDistance) return;

        dragging = true;
        BeginAnimation(LeftProperty, null);
        BeginAnimation(TopProperty, null);
        visibilityAnimating = false;
        Rect work = SystemParameters.WorkArea;
        double width = ActualWidth > 0 ? ActualWidth : Width;
        double height = ActualHeight > 0 ? ActualHeight : Height;
        restingLeft = Math.Max(work.Left, Math.Min(work.Right - width, windowStart.X + delta.X));
        restingTop = Math.Max(work.Top, Math.Min(work.Bottom - height, windowStart.Y + delta.Y));
        Left = restingLeft;
        Top = restingTop;
        e.Handled = true;
    }

    private Point PointerScreenPosition(MouseEventArgs e)
    {
        Point physical = PointToScreen(e.GetPosition(this));
        PresentationSource source = PresentationSource.FromVisual(this);
        if (source == null || source.CompositionTarget == null) return physical;
        return source.CompositionTarget.TransformFromDevice.Transform(physical);
    }

    private void OnShellMouseLeftButtonUp(object sender, MouseButtonEventArgs e)
    {
        if (!pointerDown) return;
        pointerDown = false;
        shell.ReleaseMouseCapture();
        bool wasDragging = dragging;
        dragging = false;
        e.Handled = true;
        if (!wasDragging) ToggleExpanded();
    }

    private void AnimateWindow(double targetWidth, double targetHeight, bool opening)
    {
        var ease = new SineEase { EasingMode = EasingMode.EaseInOut };
        var duration = new Duration(TimeSpan.FromMilliseconds(500));
        var widthAnim = new DoubleAnimation(ActualWidth, targetWidth, duration) { EasingFunction = ease };
        var heightAnim = new DoubleAnimation(ActualHeight, targetHeight, duration) { EasingFunction = ease };
        heightAnim.Completed += delegate {
            BeginAnimation(WidthProperty, null);
            BeginAnimation(HeightProperty, null);
            Width = targetWidth;
            Height = targetHeight;
            if (!opening) details.Visibility = Visibility.Collapsed;
        };
        BeginAnimation(WidthProperty, widthAnim, HandoffBehavior.SnapshotAndReplace);
        BeginAnimation(HeightProperty, heightAnim, HandoffBehavior.SnapshotAndReplace);
    }

    private static void AnimateOpacity(UIElement element, double target, int milliseconds)
    {
        var animation = new DoubleAnimation(target, TimeSpan.FromMilliseconds(milliseconds));
        element.BeginAnimation(OpacityProperty, animation);
    }

    private void PositionAtTop()
    {
        Rect work = SystemParameters.WorkArea;
        BeginAnimation(LeftProperty, null);
        BeginAnimation(TopProperty, null);
        restingLeft = work.Left + (work.Width - Width) / 2.0;
        restingTop = work.Top + 10;
        Left = restingLeft;
        Top = restingTop;
    }

    private void MinimizeToTaskbar()
    {
        BeginAnimation(OpacityProperty, null);
        BeginAnimation(TopProperty, null);
        visibilityAnimating = false;
        ShowInTaskbar = true;
        Topmost = false;
        WindowState = WindowState.Minimized;
    }

    private void RestoreFromTaskbarIfNeeded()
    {
        if (WindowState != WindowState.Normal || !ShowInTaskbar) return;
        ShowInTaskbar = false;
        Topmost = true;
        BeginAnimation(OpacityProperty, null);
        BeginAnimation(LeftProperty, null);
        BeginAnimation(TopProperty, null);
        Opacity = 1;
        Left = restingLeft;
        Top = restingTop;
        desiredVisible = true;
        visibilityAnimating = false;
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
        TrackResetPolling(primary, secondary);
        five.Apply(primary, active);
        weekly.Apply(secondary, active);
        summary.Text = "5H " + Remaining(primary) + "   |   7D " + Remaining(secondary);
        status.Text = active
            ? "\u5df2\u66f4\u65b0  " + DateTime.Now.ToString("HH:mm:ss") + "  |  \u6bcf 15 \u79d2\u5237\u65b0"
            : "\u5df2\u66f4\u65b0  " + DateTime.Now.ToString("HH:mm:ss");
    }

    private void CheckActivity()
    {
        active = IsCodexActive();
        UpdateIslandVisibility(active || IsCodexWindowVisible());
        if (active != wasActive) SetActiveVisual(active);
        DateTime now = DateTime.Now;
        if (resetPollingTarget != DateTime.MinValue && now > resetPollingTarget.AddSeconds(90))
        {
            resetPollingTarget = DateTime.MinValue;
            nextResetPoll = DateTime.MaxValue;
            resetPollsRemaining = 0;
        }
        double secondsSinceRefresh = (DateTime.Now - lastUsageRequest).TotalSeconds;
        bool resetPollDue = !active && resetPollsRemaining > 0 && now >= nextResetPoll;
        bool shouldRefresh = resetPollDue || (active
            ? !wasActive || secondsSinceRefresh >= 15
            : wasActive);
        if (shouldRefresh)
        {
            RequestUsage();
            if (resetPollDue)
            {
                resetPollsRemaining--;
                nextResetPoll = now.AddSeconds(30);
            }
        }
        else status.Text = active
            ? "Codex \u5bf9\u8bdd\u4e2d  |  \u6bcf 15 \u79d2\u5237\u65b0"
            : "Codex \u7a7a\u95f2";
        wasActive = active;
    }

    private void TrackResetPolling(Dictionary<string, object> primary, Dictionary<string, object> secondary)
    {
        if (resetPollingTarget != DateTime.MinValue) return;

        DateTime next = DateTime.MaxValue;
        foreach (Dictionary<string, object> window in new[] { primary, secondary })
        {
            if (window == null) continue;
            object raw;
            if (!window.TryGetValue("resetsAt", out raw) || raw == null) continue;
            try
            {
                DateTime candidate = DateTimeOffset.FromUnixTimeSeconds(Convert.ToInt64(raw)).LocalDateTime;
                if (candidate >= DateTime.Now && candidate < next) next = candidate;
            }
            catch { }
        }
        if (next == DateTime.MaxValue) return;

        resetPollingTarget = next;
        nextResetPoll = next.AddSeconds(-60);
        resetPollsRemaining = 5;
    }

    private void CheckVisibility()
    {
        if (activationEvent.WaitOne(0))
        {
            UpdateIslandVisibility(true);
            return;
        }
        UpdateIslandVisibility(active || IsCodexWindowVisible());
    }

    private void UpdateIslandVisibility(bool shouldShow)
    {
        desiredVisible = shouldShow;
        if (pointerDown) return;
        if (desiredVisible)
        {
            if (!IsVisible)
            {
                Opacity = 0;
                Top = restingTop - 12;
                Show();
                Left = restingLeft;
                Topmost = true;
                AnimateVisibility(true, restingTop);
            }
            else if (visibilityAnimating)
            {
                BeginAnimation(OpacityProperty, null);
                BeginAnimation(TopProperty, null);
                Opacity = 1;
                Left = restingLeft;
                Top = restingTop;
                visibilityAnimating = false;
            }
        }
        else if (IsVisible && !visibilityAnimating)
        {
            AnimateVisibility(false, restingTop);
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
                if (!lines[i].Contains("task_started") && !lines[i].Contains("task_complete") &&
                    !lines[i].Contains("turn_aborted")) continue;
                try
                {
                    var root = json.DeserializeObject(lines[i]) as Dictionary<string, object>;
                    if (root == null || Convert.ToString(root["type"]) != "event_msg") continue;
                    var payload = root["payload"] as Dictionary<string, object>;
                    string type = payload == null ? null : Convert.ToString(payload["type"]);
                    if (type == "task_started" || type == "task_complete" || type == "turn_aborted") return type;
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
        private readonly bool showResetDate;

        public LimitView(string name, bool showResetDate)
        {
            this.showResetDate = showResetDate;
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
                reset.Inlines.Clear();
                reset.Inlines.Add(new System.Windows.Documents.Run("\u4e0b\u4e00\u6b21\u91cd\u7f6e\u65f6\u95f4 "));
                if (showResetDate)
                {
                    reset.Inlines.Add(new System.Windows.Documents.Run(local.ToString("MM-dd HH:mm")));
                }
                else
                {
                    TimeSpan remainingTime = local - DateTime.Now;
                    if (remainingTime < TimeSpan.Zero) remainingTime = TimeSpan.Zero;
                    int hours = (int)Math.Floor(remainingTime.TotalHours);
                    int minutes = remainingTime.Minutes;
                    reset.Inlines.Add(new System.Windows.Documents.Run(local.ToString("HH:mm")) {
                        Foreground = AccentBrush,
                        FontWeight = FontWeights.Bold,
                        FontSize = 13
                    });
                    reset.Inlines.Add(new System.Windows.Documents.Run("\uff0c\u8fd8\u6709 " + hours + " \u5c0f\u65f6 " + minutes + " \u5206"));
                }
            }
            else reset.Text = "\u6682\u65e0\u91cd\u7f6e\u65f6\u95f4";
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

try {
    $app = [System.Windows.Application]::new()
    $app.ShutdownMode = [System.Windows.ShutdownMode]::OnMainWindowClose
    $window = [CodexIslandWindow]::new($CodexPath, $PSCommandPath, $activationEvent)
    $app.Run($window)
}
finally {
    $activationEvent.Dispose()
    $singleInstanceMutex.ReleaseMutex()
    $singleInstanceMutex.Dispose()
}
