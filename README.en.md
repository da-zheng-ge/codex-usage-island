# Codex Usage Island

[简体中文](README.md)

<p align="center">
  <img src="assets/codex-usage-island-preview.svg" alt="Compact and expanded Codex Usage Island preview" width="100%">
</p>

An unofficial Windows floating island that shows the remaining Codex five-hour and weekly usage limits.

Repository: <https://github.com/da-zheng-ge/codex-usage-island>

Codex Usage Island stays at the top of the desktop, animates while Codex is working, expands on click, and hides when Codex is both idle and minimized.

> This is an unofficial community project. It is not affiliated with, endorsed by, or sponsored by OpenAI.

## Features

- Remaining percentage for the five-hour and weekly limits
- Reset time in the expanded view
- Active and idle visual states
- Refreshes usage every 15 seconds only while a Codex turn is active
- Smooth WPF animations with antialiased rounded corners
- Automatically hides when Codex is idle and minimized
- No API key handling and no credential file access

## Requirements

- Windows 10 or Windows 11
- Windows PowerShell 5.1 or later
- Codex Desktop or a locally installed Codex CLI
- A signed-in Codex session

The project uses the local `codex app-server` process. The protocol is versioned with Codex and may change in future releases.

## Install

Download the release ZIP, extract it, and double-click **Install.cmd**.

Alternatively, paste the ready-made prompt from [Install with Codex](INSTALL_WITH_CODEX.md) into Codex and let it download, verify, and install the latest release.

Alternatively, run:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

The installer:

1. Copies the runtime to `%LOCALAPPDATA%\CodexUsageIsland`.
2. Creates a **Codex Usage Island** desktop shortcut.
3. Starts the island once.

The runtime discovers Codex automatically from a running app-server, Codex Desktop's local CLI directory, a VS Code extension installation, or `PATH`.

## Uninstall

Double-click **Uninstall.cmd**, or run:

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
```

The uninstaller only removes a directory containing the installation marker created by `install.ps1`.

## Usage

- Drag the island to reposition it; right-click and choose **Reset position** to return it to the top center.
- Click the island to expand or collapse details.
- Right-click and choose **Uninstall** to remove the app and desktop shortcut after confirmation.
- Right-click and choose **Exit** to close it.
- Double-click the desktop shortcut to open it again.
- `ACTIVE` means a Codex turn is running.
- `IDLE` means account usage polling is paused.

## Privacy

The app reads:

- Rate-limit percentages and reset timestamps returned by the local Codex app-server.
- Local Codex session event types (`task_started` and `task_complete`) to determine active state.
- The Codex desktop window state to decide whether the island should be visible.

It does not extract, store, or transmit prompt/response fields, access tokens, API keys, or credential files. Session-log scanning remains local and is limited to locating task lifecycle event types. The project does not include telemetry.

## Development

Run directly from the repository:

```powershell
powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\src\CodexUsageIsland.ps1
```

Optionally specify a CLI path:

```powershell
.\src\CodexUsageIsland.ps1 -CodexPath 'C:\path\to\codex.exe'
```

PowerShell 5.1 uses its built-in C# compiler, so embedded C# should remain compatible with older language syntax.

## License

[MIT](LICENSE)
