$ErrorActionPreference = 'Stop'
$exe = Join-Path $PSScriptRoot 'DesktopDDL.exe'
if (!(Test-Path $exe)) { & (Join-Path $PSScriptRoot 'build.ps1') }
$shell = New-Object -ComObject WScript.Shell
$link = $shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) 'DDL Reminder.lnk'))
$link.TargetPath = $exe
$link.WorkingDirectory = $PSScriptRoot
$link.Description = 'RHINE LAB / Desktop deadline reminder'
$link.Save()
Write-Host 'Created desktop shortcut: DDL Reminder'
