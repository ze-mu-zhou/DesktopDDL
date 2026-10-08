param([string]$Binary = '.installer-build\DesktopDDL.exe')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing,System.Windows.Forms
Add-Type -ReferencedAssemblies System.Drawing @'
using System;
using System.Drawing;
using System.Runtime.InteropServices;
public static class IconProbe {
    [DllImport("user32.dll", CharSet=CharSet.Unicode)]
    static extern IntPtr LoadImage(IntPtr instance, string name, uint type, int cx, int cy, uint flags);
    [DllImport("user32.dll")] static extern bool DestroyIcon(IntPtr icon);
    public static Icon Load(string file, int size) {
        IntPtr handle = LoadImage(IntPtr.Zero, file, 1, size, size, 0x10);
        if (handle == IntPtr.Zero) throw new InvalidOperationException("LoadImage failed: " + file);
        try { return (Icon)Icon.FromHandle(handle).Clone(); }
        finally { DestroyIcon(handle); }
    }
}
'@
function Assert($Condition, [string]$Message) {
    if (!$Condition) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}
function PixelHash([Drawing.Icon]$Icon) {
    $bitmap = $Icon.ToBitmap()
    $bytes = New-Object 'Collections.Generic.List[byte]'
    try {
        for ($y = 0; $y -lt $bitmap.Height; $y++) {
            for ($x = 0; $x -lt $bitmap.Width; $x++) {
                $bytes.AddRange([BitConverter]::GetBytes($bitmap.GetPixel($x,$y).ToArgb()))
            }
        }
        $hash = [Security.Cryptography.SHA256]::Create()
        try { return [BitConverter]::ToString($hash.ComputeHash($bytes.ToArray())) }
        finally { $hash.Dispose() }
    } finally { $bitmap.Dispose() }
}
$sizes = @(16,20,24,32,40,48,64,128,256)
foreach ($name in @('DesktopDDL', 'DesktopDDL-tray')) {
    $file = Join-Path $PSScriptRoot "assets\$name.ico"
    $bytes = [IO.File]::ReadAllBytes($file)
    Assert ([BitConverter]::ToUInt16($bytes,4) -eq $sizes.Count) "$name contains all DPI sizes"
    foreach ($size in $sizes) {
        # Test Windows' actual frame selection, including the 256px entry (width byte 0).
        # .NET Framework's legacy multi-frame constructor treats that byte as 0.
        $icon = [IconProbe]::Load($file, $size)
        try {
            Assert ($icon.Width -eq $size -and $icon.Height -eq $size) "$name loads at ${size}px"
            $bitmap = $icon.ToBitmap()
            try {
                Assert ($bitmap.GetPixel(0,0).A -eq 0 -and $bitmap.GetPixel([int]($size/2),[int]($size/2)).A -gt 240) "$name ${size}px transparency and clock center"
            } finally { $bitmap.Dispose() }
        } finally { $icon.Dispose() }
    }
}
$assembly = [Reflection.Assembly]::LoadFrom((Join-Path $PSScriptRoot $Binary))
foreach ($name in @('DesktopDDL.App.ico', 'DesktopDDL.Tray.ico')) {
    Assert ($assembly.GetManifestResourceNames() -contains $name) "Embedded resource: $name"
}
[DesktopDDL.Store]::Data = New-Object DesktopDDL.Config
$bar = $null; $manager = $null
try {
    $bar = New-Object DesktopDDL.ReminderBar
    $manager = New-Object DesktopDDL.Manager
    $tray = $bar.GetType().GetField('tray', [Reflection.BindingFlags]'NonPublic,Instance').GetValue($bar)
    $expectedTray = New-Object Drawing.Icon((Join-Path $PSScriptRoot 'assets\DesktopDDL-tray.ico'), [Windows.Forms.SystemInformation]::SmallIconSize)
    $expectedApp = New-Object Drawing.Icon((Join-Path $PSScriptRoot 'assets\DesktopDDL.ico'), [Windows.Forms.SystemInformation]::IconSize)
    try {
        Assert ((PixelHash $tray.Icon) -eq (PixelHash $expectedTray)) 'Notification area uses custom small icon'
        Assert ((PixelHash $manager.Icon) -eq (PixelHash $expectedApp)) 'Manager uses custom application icon'
        Assert ((PixelHash $bar.Icon) -eq (PixelHash $expectedApp)) 'Reminder form uses custom application icon'
    } finally { $expectedTray.Dispose(); $expectedApp.Dispose() }
} finally {
    if ($manager) { $manager.Dispose() }
    if ($bar) { $bar.Dispose() }
}
foreach ($file in @((Join-Path $PSScriptRoot $Binary), (Join-Path $PSScriptRoot 'dist\DesktopDDL-Setup.exe'))) {
    $icon = [Drawing.Icon]::ExtractAssociatedIcon($file)
    try {
        $expected = New-Object Drawing.Icon((Join-Path $PSScriptRoot 'assets\DesktopDDL.ico'), $icon.Size)
        try { Assert ((PixelHash $icon) -eq (PixelHash $expected)) "Windows executable icon: $file" }
        finally { $expected.Dispose() }
    } finally { $icon.Dispose() }
}
Write-Host 'All icon checks passed. No user data loaded or saved.'
