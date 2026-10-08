; Build with build-installer.ps1 (Inno Setup 6.5+).
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifdef TestId
  ; Isolated integration tests never register the real application.
  #define AppId "DesktopDDL-InstallerTest-" + TestId
  #define AppName "DDL Installer Test " + TestId
  #define AppMutex "Local\DesktopDDLInstallerTest-" + TestId
  #define RunValue "DesktopDDL-InstallerTest-" + TestId
  #define OutputName "DesktopDDL-Test-Setup"
#else
  #define AppId "8D9E45EA-1DF3-48D3-93E3-36574EA79427"
  #define AppName "DDL 提醒栏"
  #define AppMutex "Local\DesktopDDLReminder"
  #define RunValue "DesktopDDL"
  #define OutputName "DesktopDDL-Setup"
#endif

[Setup]
AppId={#AppId}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
VersionInfoVersion={#AppVersion}
DefaultDirName={localappdata}\Programs\DesktopDDL
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
MinVersion=10.0
WizardStyle=modern
DisableWelcomePage=no
DisableDirPage=no
AllowNoIcons=yes
OutputDir=..\dist
OutputBaseFilename={#OutputName}
Compression=lzma2
SolidCompression=yes
SetupLogging=yes
SetupIconFile=..\assets\DesktopDDL.ico
UninstallDisplayIcon={app}\DesktopDDL.exe
AppMutex={#AppMutex}
SetupMutex=Local\DesktopDDLSetup-{#AppId}
CloseApplications=no
RestartApplications=no
Uninstallable=yes

[Languages]
Name: "chinesesimplified"; MessagesFile: "ChineseSimplified.isl"

[Messages]
WelcomeLabel2=本向导将安装 [name/ver]。%n%n仅为当前 Windows 用户安装，无需管理员权限。%n%n安装、升级和卸载均保留已有事项数据。开机启动可在应用的管理窗口中设置。%n%n继续之前，请先从托盘菜单退出正在运行的提醒栏。
FinishedLabel=安装完成。%n%n程序启动后会在主屏幕右上角显示白色箭头，系统托盘也有入口。%n%n事项数据保存在本机，卸载不会删除。

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "快捷方式："

[Files]
Source: "..\.installer-build\DesktopDDL.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\使用说明.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "ChineseSimplified-LICENSE.txt"; DestDir: "{app}\licenses"; Flags: ignoreversion

[Icons]
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\DesktopDDL.exe"; WorkingDir: "{app}"; Tasks: desktopicon
Name: "{group}\{#AppName}"; Filename: "{app}\DesktopDDL.exe"; WorkingDir: "{app}"
Name: "{group}\使用说明"; Filename: "{app}\使用说明.md"
Name: "{group}\卸载 {#AppName}"; Filename: "{uninstallexe}"

[Run]
Filename: "{app}\DesktopDDL.exe"; Description: "启动 DDL 提醒栏"; Flags: nowait postinstall skipifsilent

[Code]
const
  RunKey = 'Software\Microsoft\Windows\CurrentVersion\Run';
  RunName = '{#RunValue}';

function InitializeSetup(): Boolean;
begin
  Result := IsDotNetInstalled(net4Full, 0);
  if not Result then
    MsgBox('需要 .NET Framework 4 或更高版本。请在 Windows 功能中启用 .NET Framework 4.x 后重试。', mbError, MB_OK);
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  Command: String;
begin
  // Preserve an existing opt-in, including migration from the portable edition.
  // A fresh installation never enables login startup automatically.
  if CurStep = ssPostInstall then
    if RegQueryStringValue(HKCU, RunKey, RunName, Command) then
      if not RegWriteStringValue(HKCU, RunKey, RunName,
        '"' + ExpandConstant('{app}\DesktopDDL.exe') + '"') then
        Log('Could not update the existing login startup path.');
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Command, ExePath: String;
begin
  if CurUninstallStep = usUninstall then
  begin
    ExePath := ExpandConstant('{app}\DesktopDDL.exe');
    if RegQueryStringValue(HKCU, RunKey, RunName, Command) then
      // Do not remove a startup entry now owned by another installation.
      if (CompareText(Trim(Command), '"' + ExePath + '"') = 0) or
         (CompareText(Trim(Command), ExePath) = 0) then
        RegDeleteValue(HKCU, RunKey, RunName);
  end;
  // Deliberately no [UninstallDelete]: reminders and unknown files are retained.
end;
