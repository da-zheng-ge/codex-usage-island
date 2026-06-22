param(
    [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'CodexUsageIsland'),
    [string]$ShortcutDirectory = [Environment]::GetFolderPath('Desktop'),
    [switch]$NoLaunch
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSCommandPath
$sourceScript = Join-Path $projectRoot 'src\CodexUsageIsland.ps1'
$sourceUninstaller = Join-Path $projectRoot 'uninstall.ps1'

if (-not (Test-Path -LiteralPath $sourceScript -PathType Leaf)) {
    throw "Runtime script not found: $sourceScript"
}

$installedScript = Join-Path $InstallRoot 'CodexUsageIsland.ps1'
$installedUninstaller = Join-Path $InstallRoot 'uninstall.ps1'
$installedIcon = Join-Path $InstallRoot 'CodexUsageIslandBlackV3.ico'
$marker = Join-Path $InstallRoot '.codex-usage-island-install'
$shortcutPath = Join-Path $ShortcutDirectory 'Codex Island.lnk'
$legacyShortcutPath = Join-Path $ShortcutDirectory 'Codex Usage Island.lnk'

function New-AppIcon {
    param([Parameter(Mandatory = $true)][string]$Path)

    Add-Type -AssemblyName System.Drawing
    $package = Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($package) {
        $sourceIcon = Join-Path $package.InstallLocation 'assets\Square44x44Logo.targetsize-256_altform-unplated.png'
        if (Test-Path -LiteralPath $sourceIcon -PathType Leaf) {
            $bitmap = New-Object System.Drawing.Bitmap $sourceIcon
            for ($y = 0; $y -lt $bitmap.Height; $y++) {
                for ($x = 0; $x -lt $bitmap.Width; $x++) {
                    $pixel = $bitmap.GetPixel($x, $y)
                    if ($pixel.A -eq 0) { continue }

                    $maximum = [Math]::Max($pixel.R, [Math]::Max($pixel.G, $pixel.B))
                    $minimum = [Math]::Min($pixel.R, [Math]::Min($pixel.G, $pixel.B))
                    if ($minimum -le 210 -and ($maximum - $minimum) -gt 12) {
                        $luminance = (0.2126 * $pixel.R) + (0.7152 * $pixel.G) + (0.0722 * $pixel.B)
                        $shade = [Math]::Max(7, [Math]::Min(55, [int](($luminance - 50) * 0.32)))
                        $bitmap.SetPixel($x, $y, [System.Drawing.Color]::FromArgb($pixel.A, $shade, $shade, $shade))
                    }
                }
            }

            $pngStream = New-Object System.IO.MemoryStream
            $bitmap.Save($pngStream, [System.Drawing.Imaging.ImageFormat]::Png)
            $png = $pngStream.ToArray()
            $file = [System.IO.File]::Create($Path)
            $writer = New-Object System.IO.BinaryWriter $file
            $writer.Write([UInt16]0); $writer.Write([UInt16]1); $writer.Write([UInt16]1)
            $writer.Write([Byte]0); $writer.Write([Byte]0); $writer.Write([Byte]0); $writer.Write([Byte]0)
            $writer.Write([UInt16]1); $writer.Write([UInt16]32)
            $writer.Write([UInt32]$png.Length); $writer.Write([UInt32]22); $writer.Write($png)
            $writer.Dispose()
            $pngStream.Dispose()
            $bitmap.Dispose()
            return
        }
    }

    $bitmap = New-Object System.Drawing.Bitmap 256, 256
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.Clear([System.Drawing.Color]::Transparent)

    $background = New-Object System.Drawing.Drawing2D.GraphicsPath
    $background.AddArc(12, 12, 72, 72, 180, 90)
    $background.AddArc(172, 12, 72, 72, 270, 90)
    $background.AddArc(172, 172, 72, 72, 0, 90)
    $background.AddArc(12, 172, 72, 72, 90, 90)
    $background.CloseFigure()
    $gradient = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.Point 24, 20),
        (New-Object System.Drawing.Point 232, 236),
        ([System.Drawing.Color]::FromArgb(255, 54, 54, 58)),
        ([System.Drawing.Color]::FromArgb(255, 3, 3, 4))
    )
    $graphics.FillPath($gradient, $background)

    $borderPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(150, 118, 118, 124)), 4
    $graphics.DrawPath($borderPen, $background)

    $glyphPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::White), 19
    $glyphPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $glyphPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $glyphPen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    $graphics.DrawLine($glyphPen, 67, 83, 112, 128)
    $graphics.DrawLine($glyphPen, 112, 128, 67, 173)
    $graphics.DrawLine($glyphPen, 137, 169, 194, 169)

    $pngStream = New-Object System.IO.MemoryStream
    $bitmap.Save($pngStream, [System.Drawing.Imaging.ImageFormat]::Png)
    $png = $pngStream.ToArray()
    $file = [System.IO.File]::Create($Path)
    $writer = New-Object System.IO.BinaryWriter $file
    $writer.Write([UInt16]0)
    $writer.Write([UInt16]1)
    $writer.Write([UInt16]1)
    $writer.Write([Byte]0)
    $writer.Write([Byte]0)
    $writer.Write([Byte]0)
    $writer.Write([Byte]0)
    $writer.Write([UInt16]1)
    $writer.Write([UInt16]32)
    $writer.Write([UInt32]$png.Length)
    $writer.Write([UInt32]22)
    $writer.Write($png)
    $writer.Dispose()

    $pngStream.Dispose()
    $glyphPen.Dispose()
    $borderPen.Dispose()
    $gradient.Dispose()
    $background.Dispose()
    $graphics.Dispose()
    $bitmap.Dispose()
}

New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null
Copy-Item -LiteralPath $sourceScript -Destination $installedScript -Force
Copy-Item -LiteralPath $sourceUninstaller -Destination $installedUninstaller -Force
New-AppIcon -Path $installedIcon
Set-Content -LiteralPath $marker -Value 'Codex Usage Island installation marker' -Encoding ASCII

New-Item -ItemType Directory -Path $ShortcutDirectory -Force | Out-Null
Remove-Item -LiteralPath $legacyShortcutPath -Force -ErrorAction SilentlyContinue
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = (Get-Command powershell.exe).Source
$shortcut.Arguments = '-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $installedScript + '"'
$shortcut.WorkingDirectory = $InstallRoot
$shortcut.IconLocation = $installedIcon + ',0'
$shortcut.Description = 'Open Codex Usage Island'
$shortcut.Save()

if (-not $NoLaunch) {
    Start-Process -FilePath 'powershell.exe' `
        -ArgumentList @('-NoProfile', '-STA', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-File', $installedScript) `
        -WindowStyle Hidden
}

Write-Host "Installed Codex Usage Island to: $InstallRoot"
Write-Host "Desktop shortcut: $shortcutPath"
