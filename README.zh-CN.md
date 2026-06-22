# Codex Usage Island

[English](README.md)

一个非官方的 Windows Codex 用量灵动岛，显示 5 小时和每周限额的剩余百分比。

项目地址：<https://github.com/da-zheng-ge/codex-usage-island>

> 本项目是非官方社区项目，与 OpenAI 没有关联，也未获得 OpenAI 的认可或赞助。

## 功能

- 显示 5 小时和每周限额的剩余百分比
- 展开后显示额度重置时间
- Codex 工作时显示动态效果
- 仅在 Codex 对话进行中每 15 秒刷新一次用量
- WPF 抗锯齿圆角与平滑动画
- Codex 空闲且最小化时自动隐藏
- 不处理 API Key，也不读取认证文件

## 系统要求

- Windows 10 或 Windows 11
- Windows PowerShell 5.1 或更高版本
- Codex Desktop 或本地安装的 Codex CLI
- 已登录的 Codex 会话

本项目使用本机的 `codex app-server`。该协议跟随 Codex 版本演进，未来版本可能发生变化。

## 安装

从 GitHub Releases 下载 ZIP，解压后双击 **Install.cmd** 即可安装。

也可以把 [使用 Codex 安装](INSTALL_WITH_CODEX.md) 中的中文提示词直接发送给 Codex，让它自动下载、校验并安装最新版本。

也可以运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

安装程序会：

1. 将运行文件复制到 `%LOCALAPPDATA%\CodexUsageIsland`。
2. 在桌面创建 **Codex Usage Island** 快捷方式。
3. 启动一次灵动岛。

运行程序会依次从正在运行的 app-server、Codex Desktop 本地 CLI 目录、VS Code 扩展目录和 `PATH` 中自动查找 Codex。

## 卸载

双击 **Uninstall.cmd**，或在下载的仓库目录运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
```

卸载程序只会删除包含安装标记的目录，避免误删其他文件。

## 使用

- 单击灵动岛展开或收起详情。
- 右键选择“退出”关闭。
- 双击桌面快捷方式重新打开。
- `ACTIVE` 表示 Codex 正在执行任务。
- `IDLE` 表示账号用量轮询已暂停。

## 隐私

程序只读取本地 app-server 返回的限额数据、会话日志中的任务生命周期事件类型，以及 Codex 窗口的显示状态。

程序不会提取、保存或传输提示词、回复、访问令牌、API Key 或认证文件，不包含遥测功能。

## 许可证

[MIT](LICENSE)
