param(
    [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'CodexUsageIsland'),
    [string]$ShortcutDirectory = [Environment]::GetFolderPath('Desktop')
)

$ErrorActionPreference = 'Stop'
$marker = Join-Path $InstallRoot '.codex-usage-island-install'
$installedScript = Join-Path $InstallRoot 'CodexUsageIsland.ps1'
$shortcutPath = Join-Path $ShortcutDirectory 'Codex Island.lnk'
$legacyShortcutPath = Join-Path $ShortcutDirectory 'Codex Usage Island.lnk'

if (-not (Test-Path -LiteralPath $marker -PathType Leaf)) {
    throw "Refusing to remove an unrecognized directory: $InstallRoot"
}

$escapedScript = [regex]::Escape($installedScript)
Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match "-File\s+`"?$escapedScript" } |
    ForEach-Object {
        $parentProcessId = $_.ProcessId
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object { $_.ParentProcessId -eq $parentProcessId } |
            ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
        Stop-Process -Id $parentProcessId -Force -ErrorAction SilentlyContinue
    }

Remove-Item -LiteralPath $shortcutPath -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $legacyShortcutPath -Force -ErrorAction SilentlyContinue

$runningFromInstallRoot = $PSCommandPath.StartsWith($InstallRoot, [StringComparison]::OrdinalIgnoreCase)
if ($runningFromInstallRoot) {
    $escapedRoot = $InstallRoot.Replace("'", "''")
    $cleanup = "Start-Sleep -Milliseconds 700; Remove-Item -LiteralPath '$escapedRoot' -Recurse -Force"
    Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-WindowStyle', 'Hidden', '-Command', $cleanup) -WindowStyle Hidden
}
else {
    Remove-Item -LiteralPath $InstallRoot -Recurse -Force
}

Write-Host 'Codex Usage Island was uninstalled.'
