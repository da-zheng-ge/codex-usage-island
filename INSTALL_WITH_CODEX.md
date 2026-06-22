# Install with Codex

After this repository is public, replace `<YOUR_GITHUB_USERNAME>` below and share the resulting sentence.

## Short prompt

```text
Please install the latest release of https://github.com/<YOUR_GITHUB_USERNAME>/codex-usage-island on this Windows computer. Download the release ZIP and SHA-256 file, verify the checksum, extract it to a temporary directory, run Install.cmd, and confirm that the Codex Usage Island desktop shortcut was created. Do not install or replace Codex itself.
```

## Chinese prompt

```text
请在这台 Windows 电脑上安装 https://github.com/<YOUR_GITHUB_USERNAME>/codex-usage-island 的最新正式版。下载 Release 中的 ZIP 和 SHA-256 文件并校验，解压到临时目录，运行 Install.cmd，最后确认桌面已经创建 Codex Usage Island 快捷方式。不要安装或替换 Codex 本身。
```

## Expected Codex workflow

1. Resolve the repository's latest GitHub Release.
2. Download `codex-usage-island-v*.zip` and its `.sha256` file.
3. Verify the archive SHA-256 before executing project files.
4. Extract the archive into a temporary directory.
5. Run `Install.cmd` or `install.ps1` from the extracted release.
6. Confirm `%LOCALAPPDATA%\CodexUsageIsland\CodexUsageIsland.ps1` exists.
7. Confirm the **Codex Usage Island** desktop shortcut exists.
8. Remove only the temporary download and extraction directory.

Codex may request approval before downloading files or running the installer, depending on the user's permissions configuration.
