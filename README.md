# DesktopDDL · DDL 提醒栏

Windows 桌面截止日期提醒工具。平时只在主屏幕右上角显示一个白色箭头，鼠标悬停后展开待办；原生 WinForms 实现，无需 Python、Node.js 或 Electron。

[下载安装包](https://github.com/ze-mu-zhou/DesktopDDL/releases/latest) · [使用说明](使用说明.md) · [性能与测试](性能与测试.md)

<p align="center">
  <img src="assets/DesktopDDL.png" width="128" height="128" alt="DesktopDDL 图标：橄榄绿切角档案与时钟">
</p>

## 安装

1. 在 [Releases](https://github.com/ze-mu-zhou/DesktopDDL/releases/latest) 下载 **`DesktopDDL-Setup.exe`**，不是下方的 Source code 压缩包。
2. 双击运行中文安装向导，默认安装到 `%LOCALAPPDATA%\Programs\DesktopDDL`，无需管理员权限。
3. 从桌面或开始菜单启动；悬停右上角白色箭头查看待办，双击箭头或托盘图标打开管理窗口。

支持 Windows 10/11，依赖系统 .NET Framework 4.x。安装包未做代码签名，可能显示未知发布者提示，请确认下载来源。Release 同时提供 SHA-256 校验文件，可在 PowerShell 中核对：

```powershell
Get-FileHash .\DesktopDDL-Setup.exe -Algorithm SHA256
```

## 功能

- 按截止时间排序，逾期标红；支持添加、修改、完成、恢复和删除事项。
- 两级悬停展开，支持自定义展开数量；收起后不轮询或持续刷新。
- 事项说明支持文字、粘贴截图，以及本地文件链接。
- 图文内容保存在本机；文件链接指向原文件，不会把文件本身复制到事项中。
- 无边框管理窗口、托盘入口、可选登录启动。
- 原创切角档案与时钟图标，程序、安装器和小尺寸托盘图标配套。
- 不联网、不上传事项，不发送通知或播放声音。

## 数据与卸载

数据保存在 `%LOCALAPPDATA%\DesktopDDL\reminders.json`，上一版保存在 `reminders.json.bak`。重要数据建议另外备份整个数据目录。

安装版与便携版共用此目录，因此安装或升级后会自动读取已有事项，无需重复导入。卸载保留数据；只有手动删除数据目录才会清除事项。

安装或卸载前，请从托盘菜单正常退出。安装器会阻止覆盖运行中的程序，不强制结束进程。卸载可从 Windows「设置 → 应用」或开始菜单进行。

## 从源码构建

在 Windows PowerShell 中执行：

```powershell
# 构建便携程序 DesktopDDL.exe
powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1

# 构建 dist\DesktopDDL-Setup.exe，需要另外安装 Inno Setup 6.5+
powershell -NoProfile -ExecutionPolicy Bypass -File .\build-installer.ps1
```

无需 Visual Studio。应用使用系统自带 .NET Framework C# 编译器；安装器构建说明见 [installer/README.md](installer/README.md)。图标已包含在仓库中，修改图案后可运行 `assets\GenerateIcons.ps1` 重新生成。

## 测试

```powershell
powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\Test.ps1
powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\TestRequirements.ps1
powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\TestFileLinks.ps1
powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\TestPerformance.ps1

# 先构建安装包，再运行图标及安装流程测试
powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\TestIcons.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\TestInstaller.ps1 -CompilerPath "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
```

事项相关测试使用临时数据目录，安装器测试使用独立应用标识，不读写真实事项。界面测试前请退出正式程序，测试期间不要操作鼠标。可选的剪贴板测试需显式传入 `-TestClipboard`。

## 说明与致谢

界面参考莱茵生命风格；这是非官方个人工具，与《明日方舟》官方无隶属关系。视觉参考链接见 [使用说明](使用说明.md)，未复制其代码、图片、字体或音频。

安装器使用 Inno Setup，中文翻译来自 [kira-96/Inno-Setup-Chinese-Simplified-Translation](https://github.com/kira-96/Inno-Setup-Chinese-Simplified-Translation)，其 MIT 许可保留在 [installer/ChineseSimplified-LICENSE.txt](installer/ChineseSimplified-LICENSE.txt)。该许可仅适用于对应第三方翻译文件。
