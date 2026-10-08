param([string]$CompilerPath = "$PSScriptRoot\.build-tools\InnoSetup\ISCC.exe")
$ErrorActionPreference = 'Stop'
function Assert($Condition, [string]$Message) {
    if (!$Condition) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}
function Invoke-Setup([string]$File, [string[]]$Options, [bool]$ExpectSuccess = $true) {
    $p = Start-Process -FilePath $File -ArgumentList $Options -Wait -PassThru
    if ($ExpectSuccess -and $p.ExitCode -ne 0) { throw "Setup failed: $($p.ExitCode) ($File)" }
    return $p.ExitCode
}
function Wait-Removed([string]$File) {
    for ($i = 0; $i -lt 50 -and (Test-Path -LiteralPath $File); $i++) { Start-Sleep -Milliseconds 100 }
    Assert (!(Test-Path -LiteralPath $File)) "Removed $File"
}

Assert (Test-Path -LiteralPath "$PSScriptRoot\.installer-build\DesktopDDL.exe") 'Staged application exists (run build-installer.ps1 first)'
$id = [Guid]::NewGuid().ToString('N')
$testName = "DDL Installer Test $id"
$runName = "DesktopDDL-InstallerTest-$id"
$work = Join-Path $PSScriptRoot ".installer-build\test-$id"
# Exercise both Unicode and spaces in the installation path.
$install = Join-Path $work ("Install " + [char]0x6D4B + [char]0x8BD5 + ' App')
$setup = Join-Path $work 'DesktopDDL-Test-Setup.exe'
$exe = Join-Path $install 'DesktopDDL.exe'
$uninstaller = Join-Path $install 'unins000.exe'
$desktopLink = Join-Path ([Environment]::GetFolderPath('Desktop')) "$testName.lnk"
$group = Join-Path ([Environment]::GetFolderPath('Programs')) $testName
$uninstallKey = "Software\Microsoft\Windows\CurrentVersion\Uninstall\DesktopDDL-InstallerTest-${id}_is1"
$run = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Software\Microsoft\Windows\CurrentVersion\Run')
$mutex = $null
New-Item -ItemType Directory -Path $work -Force | Out-Null
try {
    & $CompilerPath "/DTestId=$id" "/O$work" "$PSScriptRoot\installer\DesktopDDL.iss"
    Assert ($LASTEXITCODE -eq 0) 'Compiled isolated test installer'
    $options = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', "/DIR=`"$install`"")

    $mutex = New-Object Threading.Mutex($false, "Local\DesktopDDLInstallerTest-$id")
    $code = Invoke-Setup $setup ($options + "/LOG=`"$work\blocked.log`"") $false
    Assert ($code -ne 0 -and !(Test-Path -LiteralPath $exe)) 'Running application blocks installation without writing files'
    $mutex.Dispose(); $mutex = $null

    Invoke-Setup $setup ($options + @('/TASKS=desktopicon', "/LOG=`"$work\install.log`"")) | Out-Null
    Assert (Test-Path -LiteralPath $exe) 'Fresh installation to Unicode path'
    Assert ((Get-FileHash -LiteralPath $exe).Hash -eq (Get-FileHash -LiteralPath "$PSScriptRoot\.installer-build\DesktopDDL.exe").Hash) 'Installed executable matches current source build'
    Assert (Test-Path -LiteralPath $desktopLink) 'Desktop shortcut created'
    $shell = New-Object -ComObject WScript.Shell
    Assert ($shell.CreateShortcut($desktopLink).TargetPath -eq $exe) 'Desktop shortcut targets installed application'
    Assert (Test-Path -LiteralPath (Join-Path $group "$testName.lnk")) 'Start menu shortcut created'
    Assert ($null -eq $run.GetValue($runName)) 'Fresh install leaves login startup disabled'
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($uninstallKey)
    Assert ($null -ne $key) 'Registered in current-user Windows app list'
    Assert ($key.GetValue('DisplayVersion') -eq '1.0.0') 'Registered version'
    $key.Dispose()

    # Upgrade must not recursively clear the app directory or overwrite user files.
    $sentinel = Join-Path $install 'user-data-must-survive.json'
    [IO.File]::WriteAllText($sentinel, '{"keep":true}')
    $run.SetValue($runName, '"C:\old portable\DesktopDDL.exe"')
    Invoke-Setup $setup ($options + "/LOG=`"$work\upgrade.log`"") | Out-Null
    Assert ([IO.File]::ReadAllText($sentinel) -eq '{"keep":true}') 'Upgrade preserves unknown user files'
    Assert ($run.GetValue($runName) -eq ('"' + $exe + '"')) 'Upgrade migrates existing login startup path'

    $mutex = New-Object Threading.Mutex($false, "Local\DesktopDDLInstallerTest-$id")
    $code = Invoke-Setup $uninstaller @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART') $false
    Assert ($code -ne 0 -and (Test-Path -LiteralPath $exe)) 'Running application blocks uninstallation'
    $mutex.Dispose(); $mutex = $null

    Invoke-Setup $uninstaller @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', "/LOG=`"$work\uninstall.log`"") | Out-Null
    Wait-Removed $exe
    Wait-Removed $uninstaller
    Assert (!(Test-Path -LiteralPath $desktopLink)) 'Desktop shortcut removed'
    Assert (!(Test-Path -LiteralPath $group)) 'Start menu shortcuts removed'
    Assert ($null -eq $run.GetValue($runName)) 'Owned login startup entry removed'
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($uninstallKey)
    Assert ($null -eq $key) 'Uninstall registration removed'
    Assert ([IO.File]::ReadAllText($sentinel) -eq '{"keep":true}') 'Uninstall preserves unknown user files'

    Invoke-Setup $setup ($options + @('/TASKS=', "/LOG=`"$work\reinstall.log`"")) | Out-Null
    Assert (!(Test-Path -LiteralPath $desktopLink)) 'Desktop shortcut can be disabled'
    $run.SetValue($runName, '"C:\another copy\DesktopDDL.exe"')
    Invoke-Setup $uninstaller @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART') | Out-Null
    Wait-Removed $exe
    Wait-Removed $uninstaller
    Assert ($run.GetValue($runName) -eq '"C:\another copy\DesktopDDL.exe"') 'Uninstall preserves startup entry owned by another copy'
    Write-Host "All installer tests passed. Logs: $work"
}
finally {
    if ($mutex) { $mutex.Dispose() }
    if (Test-Path -LiteralPath $uninstaller) {
        Invoke-Setup $uninstaller @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART') | Out-Null
    }
    $run.DeleteValue($runName, $false)
    $run.Dispose()
    # Only remove the random test folder; keep installer and logs for diagnosis.
    if (Test-Path -LiteralPath $install) { Remove-Item -LiteralPath $install -Recurse -Force }
}
