param(
    [ValidatePattern('^\d+\.\d+\.\d+(\.\d+)?$')]
    [string]$Version = '1.0.0',
    [string]$CompilerPath
)
$ErrorActionPreference = 'Stop'

if (!$CompilerPath) {
    $candidates = @(
        "$PSScriptRoot\.build-tools\InnoSetup\ISCC.exe",
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
        "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
        "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
    )
    $command = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($command) { $candidates += $command.Source }
    $CompilerPath = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}
if (!$CompilerPath -or !(Test-Path -LiteralPath $CompilerPath)) {
    throw 'Inno Setup 6.5+ is required: https://jrsoftware.org/isdl.php . Or pass -CompilerPath to ISCC.exe.'
}

# Stage a fresh executable without replacing the user's running portable copy.
New-Item -ItemType Directory -Force -Path "$PSScriptRoot\.installer-build" | Out-Null
& "$PSScriptRoot\build.ps1" -OutputName '.installer-build\DesktopDDL.exe'
& $CompilerPath "/DAppVersion=$Version" "$PSScriptRoot\installer\DesktopDDL.iss"
if ($LASTEXITCODE -ne 0) { throw "Installer build failed: $LASTEXITCODE" }
$installer = Join-Path $PSScriptRoot 'dist\DesktopDDL-Setup.exe'
$hash = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText("$installer.sha256", "$hash  DesktopDDL-Setup.exe`r`n", [Text.Encoding]::ASCII)
Write-Host "Installer: $installer"
Write-Host "SHA256: $hash"
