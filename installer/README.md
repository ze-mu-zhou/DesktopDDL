# Windows 安装包

成品：`dist\DesktopDDL-Setup.exe`。仅发送这个 EXE 即可，不需要附带源码或编译工具；安装过程不联网。旁边的 `.sha256` 文件用于校验下载完整性，不是数字签名。

## 重新构建

要求 Windows 10/11、自带的 .NET Framework 编译器，以及 **Inno Setup 6.5 或更高版本**。本次使用 Inno Setup 6.7.3，编译器放在 `.build-tools\InnoSetup`；构建脚本也会查找常见安装位置和 PATH。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build-installer.ps1
# 自定义发布版本或编译器位置：
powershell -NoProfile -ExecutionPolicy Bypass -File .\build-installer.ps1 -Version 1.0.1 -CompilerPath "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
```

编译器下载：https://jrsoftware.org/isdl.php 。构建脚本不自动下载或安装依赖。商业分发请核对所使用 Inno Setup 版本的许可要求。

每次先从当前源码构建 `.installer-build\DesktopDDL.exe`，再嵌入安装包，不覆盖或关闭正在运行的便携版程序。`dist` 中只放正式安装包及其 SHA-256 校验文件。

## 安装行为

- 简体中文向导；仅当前用户安装，默认目录 `%LOCALAPPDATA%\Programs\DesktopDDL`，不请求管理员权限。
- 可选择安装目录和桌面快捷方式，开始菜单提供启动、说明和卸载入口。
- 固定 AppId 用于覆盖升级，不要在后续版本中更换。
- 使用应用原有的 `Local\DesktopDDLReminder` 互斥量，安装和卸载前要求用户正常退出，不强制结束进程。
- 首次安装不启用开机启动；若用户已有 `HKCU\Software\Microsoft\Windows\CurrentVersion\Run\DesktopDDL` 设置，安装后迁移到新路径。卸载只删除仍指向当前安装的启动项。
- 不写入、不打包、不删除 `%LOCALAPPDATA%\DesktopDDL` 下的事项或备份；没有递归清理安装目录的卸载规则，未知文件也保留。
- 不删除原便携版程序或其旧快捷方式。
- 未配置代码签名；正式发布可按 Inno Setup 的 SignTool 文档接入自己的证书。

静默安装参数：`/VERYSILENT /SUPPRESSMSGBOXES /NORESTART`，可加 `/DIR="目标目录"`、`/TASKS=desktopicon` 或 `/TASKS=`。静默安装不自动启动应用；应用正在运行时返回非零退出码。

## 集成测试

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\TestInstaller.ps1
```

如编译器不在项目本地目录，请传 `-CompilerPath`。测试通过 `TestId` 编译独立安装包，随机隔离 AppId、互斥量、开机启动注册表值、安装目录及快捷方式；不安装或卸载正式版本，不启动应用，不读写真实事项数据。测试目录包含中文和空格。

已验证：首次安装、EXE 哈希一致性、快捷方式目标、系统卸载注册、开机启动默认关闭、覆盖升级、启动路径迁移、运行中安装/卸载拦截、卸载清理、保留未知文件、不创建桌面快捷方式、保留指向另一份程序的启动项。测试后移除测试安装，日志留在 `.installer-build\test-*`。

若在 Windows PowerShell 5.1 中遇到 PowerShell 7 模块误加载，可在当前进程先设置 `$env:PSModulePath = "$PSHOME\Modules"` 再执行脚本，不必修改系统环境变量。

## 翻译来源

`ChineseSimplified.isl` 来自 https://github.com/kira-96/Inno-Setup-Chinese-Simplified-Translation ，提交 `1ff90acc4ed4aee82b1cda43253243deee3daed4`。原 MIT 许可保留在 `ChineseSimplified-LICENSE.txt`，并随应用安装到 `licenses` 子目录。
