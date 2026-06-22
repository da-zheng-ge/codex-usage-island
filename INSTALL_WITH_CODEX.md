# Install with Codex

## Short prompt

```text
Please install Codex Usage Island v1.0.0 from https://github.com/da-zheng-ge/codex-usage-island on this Windows computer. Download the v1.0.0 tag source archive to a temporary directory, extract it, run Install.cmd, and confirm that the Codex Usage Island desktop shortcut was created. Do not install or replace Codex itself.
```

## Chinese prompt

```text
请在这台 Windows 电脑上安装 https://github.com/da-zheng-ge/codex-usage-island 的 v1.0.0。下载 v1.0.0 标签的源码压缩包到临时目录，解压后运行 Install.cmd，最后确认桌面已经创建 Codex Usage Island 快捷方式。不要安装或替换 Codex 本身。
```

## Expected Codex workflow

1. Download `https://github.com/da-zheng-ge/codex-usage-island/archive/refs/tags/v1.0.0.zip`.
2. Extract the archive into a temporary directory.
3. Run `Install.cmd` or `install.ps1` from the extracted source archive.
4. Confirm `%LOCALAPPDATA%\CodexUsageIsland\CodexUsageIsland.ps1` exists.
5. Confirm the **Codex Usage Island** desktop shortcut exists.
6. Remove only the temporary download and extraction directory.

Codex may request approval before downloading files or running the installer, depending on the user's permissions configuration.
