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
$marker = Join-Path $InstallRoot '.codex-usage-island-install'
$shortcutPath = Join-Path $ShortcutDirectory 'Codex Usage Island.lnk'

New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null
Copy-Item -LiteralPath $sourceScript -Destination $installedScript -Force
Copy-Item -LiteralPath $sourceUninstaller -Destination $installedUninstaller -Force
Set-Content -LiteralPath $marker -Value 'Codex Usage Island installation marker' -Encoding ASCII

New-Item -ItemType Directory -Path $ShortcutDirectory -Force | Out-Null
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = (Get-Command powershell.exe).Source
$shortcut.Arguments = '-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $installedScript + '"'
$shortcut.WorkingDirectory = $InstallRoot
$shortcut.IconLocation = (Get-Command powershell.exe).Source + ',0'
$shortcut.Description = 'Open Codex Usage Island'
$shortcut.Save()

if (-not $NoLaunch) {
    Start-Process -FilePath 'powershell.exe' `
        -ArgumentList @('-NoProfile', '-STA', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-File', $installedScript) `
        -WindowStyle Hidden
}

Write-Host "Installed Codex Usage Island to: $InstallRoot"
Write-Host "Desktop shortcut: $shortcutPath"
