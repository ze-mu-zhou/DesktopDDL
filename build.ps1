param([string]$OutputName = 'DesktopDDL.exe')
$ErrorActionPreference = 'Stop'
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (!(Test-Path $compiler)) { $compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
& $compiler /nologo /target:winexe /optimize+ /codepage:65001 /win32manifest:"$PSScriptRoot\app.manifest" /win32icon:"$PSScriptRoot\assets\DesktopDDL.ico" /resource:"$PSScriptRoot\assets\DesktopDDL.ico",DesktopDDL.App.ico /resource:"$PSScriptRoot\assets\DesktopDDL-tray.ico",DesktopDDL.Tray.ico /out:"$PSScriptRoot\$OutputName" /reference:System.dll /reference:System.Core.dll /reference:System.Drawing.dll /reference:System.Windows.Forms.dll /reference:System.Runtime.Serialization.dll "$PSScriptRoot\Reminder.cs" "$PSScriptRoot\AppIcons.cs" "$PSScriptRoot\NativeSurface.cs" "$PSScriptRoot\ReminderBar.cs" "$PSScriptRoot\Theme.cs" "$PSScriptRoot\RequirementsEditor.cs" "$PSScriptRoot\Manager.cs"
if ($LASTEXITCODE -ne 0) { throw 'Build failed.' }
Write-Host "Built $OutputName"
