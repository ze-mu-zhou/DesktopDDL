param([string]$Binary = 'DesktopDDL.exe')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing, System.Runtime.Serialization
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class TestNative {
 [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
 [DllImport("user32.dll")] public static extern uint GetGuiResources(IntPtr p, uint f);
}
'@
[TestNative]::SetProcessDPIAware() | Out-Null
[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Reflection.Assembly]::LoadFrom((Join-Path $PSScriptRoot $Binary)) | Out-Null
function Assert($condition, $message) { if (!$condition) { throw "FAIL: $message" }; Write-Host "PASS: $message" }
function Pump([int]$ms) {
 $watch = [System.Diagnostics.Stopwatch]::StartNew()
 while ($watch.ElapsedMilliseconds -lt $ms) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 5 }
}
function Field($obj, $name) { $obj.GetType().GetField($name, [System.Reflection.BindingFlags]'NonPublic,Instance').GetValue($obj) }
function InvokePrivate($obj, $name, [object[]]$arguments) {
 $obj.GetType().GetMethod($name, [System.Reflection.BindingFlags]'NonPublic,Instance').Invoke($obj, $arguments) | Out-Null
}
function MoveTo([int]$x, [int]$y) { [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($x, $y); Pump 25 }
function Snapshot($form, $name) {
 $image = New-Object System.Drawing.Bitmap($form.Width, $form.Height)
 $form.DrawToBitmap($image, (New-Object System.Drawing.Rectangle([System.Drawing.Point]::Empty, $form.Size)))
 $image.Save((Join-Path $PSScriptRoot $name), [System.Drawing.Imaging.ImageFormat]::Png); $image.Dispose()
}
function ScreenSnapshot($rect, $name) {
 $image = New-Object System.Drawing.Bitmap($rect.Width, $rect.Height)
 $g = [System.Drawing.Graphics]::FromImage($image)
 $g.CopyFromScreen($rect.Location, [System.Drawing.Point]::Empty, $rect.Size)
 $image.Save((Join-Path $PSScriptRoot $name), [System.Drawing.Imaging.ImageFormat]::Png)
 $g.Dispose(); $image.Dispose()
}
$sandbox = Join-Path $env:TEMP ('DesktopDDL-test-' + [Guid]::NewGuid().ToString('N'))
# .NET Framework reflection permits test-only redirection of these static readonly fields.
[DesktopDDL.Store].GetField('Folder').SetValue($null, $sandbox)
[DesktopDDL.Store].GetField('FileName').SetValue($null, (Join-Path $sandbox 'reminders.json'))
Assert ([DesktopDDL.Store]::FileName.StartsWith($sandbox)) 'Persistence isolated from user data'
[DesktopDDL.Store]::Data = New-Object DesktopDDL.Config
$names = @('Submit research report', 'Review experiment results', 'Prepare presentation', 'Back up lab documents', 'Weekly planning')
for ($i = 4; $i -ge 0; $i--) {
 $item = New-Object DesktopDDL.Item; $item.Title = $names[$i]; $item.Due = [DateTime]::Now.AddHours(($i + 1) * 10)
 [DesktopDDL.Store]::Data.Items.Add($item)
}
$done = New-Object DesktopDDL.Item; $done.Title = 'Completed'; $done.Done = $true; $done.Due = [DateTime]::Now.AddDays(-2)
[DesktopDDL.Store]::Data.Items.Add($done)
Assert ([DesktopDDL.Store]::Pending().Count -eq 5) 'Completed items excluded'
Assert ([DesktopDDL.Store]::Pending()[0].Title -eq $names[0]) 'Deadline order'
Assert ([DesktopDDL.Store]::Save()) 'Atomic initial save'
Assert ([DesktopDDL.Store]::Save()) 'Atomic replacement save'
Assert (Test-Path ([DesktopDDL.Store]::FileName + '.bak')) 'Previous file backed up'
[DesktopDDL.Store]::Load()
Assert ([DesktopDDL.Store]::Data.Items.Count -eq 6) 'JSON round-trip'
$cursor = [System.Windows.Forms.Cursor]::Position
$bar = New-Object DesktopDDL.ReminderBar
try {
 MoveTo 100 400; $bar.Show(); Pump 200
 $anchor = $bar.Bounds; $arrowPresents = $bar.PresentCount
 Assert ($bar.Stage -eq 0 -and $bar.Idle -and !$bar.PanelVisible) 'Collapsed: no polling or redraw timers'
 MoveTo ($bar.Left + $bar.Width / 2) ($bar.Top + $bar.Height / 2); Pump 350
 Assert ($bar.Stage -eq 1 -and $bar.PanelVisible) 'Arrow hover reveals first item'
 Assert ($bar.Bounds -eq $anchor -and $bar.PresentCount -eq $arrowPresents) 'Arrow neither moves nor repaints while sliding'
 $oneHeight = $bar.PanelBounds.Height; $cache = $bar.CacheBuilds; $oneCacheBytes = $bar.PanelCacheBytes
 MoveTo ($bar.PanelBounds.Left + 80) ($bar.PanelBounds.Top + 45); Pump 600
 Assert ($bar.Stage -eq 2 -and $bar.PanelBounds.Height -gt $oneHeight * 4) "Second hover expands five rows (stage=$($bar.Stage), pointer=$([System.Windows.Forms.Cursor]::Position), panel=$($bar.PanelBounds))"
 Assert ($bar.CacheBuilds -eq $cache + 1) 'Expansion builds additional rows once; animation reuses cached pixels'
 Assert ($bar.PanelCacheBytes -gt $oneCacheBytes * 4) 'First-stage cache holds only one row'
 $cache = $bar.CacheBuilds; $presents = $bar.PanelPresentCount
 [DesktopDDL.Store]::NotifyChanged(); Pump 40
 Assert ($bar.CacheBuilds -eq $cache -and $bar.PanelPresentCount -eq $presents) 'Unchanged visible content skips rebuilding and presenting'
 $rect = [System.Drawing.Rectangle]::Union($bar.Bounds, $bar.PanelBounds)
 ScreenSnapshot $rect 'preview-expanded.png'
 [DesktopDDL.Store]::Data.VisibleCount = 2; [DesktopDDL.Store]::NotifyChanged(); Pump 300
 Assert ($bar.PanelBounds.Height -gt $oneHeight -and $bar.PanelBounds.Height -lt $oneHeight * 3) 'Live count update'
 [DesktopDDL.Store]::Data.VisibleCount = 1; [DesktopDDL.Store]::NotifyChanged(); Pump 300
 Assert ($bar.PanelBounds.Height -eq $oneHeight) 'One-row limit'
 MoveTo 100 400; Pump 850
 Assert ($bar.Stage -eq 0 -and !$bar.PanelVisible -and $bar.Idle) 'Leaving collapses and stops all four timers'
 Assert (!$bar.PanelHasSurface) 'Collapsed panel bitmap released'
 $present = $bar.PanelPresentCount; Pump 1100
 Assert ($bar.PanelPresentCount -eq $present) 'Zero hidden repaints'
 [DesktopDDL.Store]::Data.VisibleCount = 5; [DesktopDDL.Store]::NotifyChanged()
 $testProcess = [System.Diagnostics.Process]::GetCurrentProcess(); $handle = $testProcess.Handle
 # Warm up font/GDI caches, then stress re-entry and cancellation.
 MoveTo ($bar.Left + $bar.Width / 2) ($bar.Top + $bar.Height / 2); Pump 280; MoveTo 100 400; Pump 800
 $gdi = [TestNative]::GetGuiResources($handle, 0)
 for ($i=0; $i -lt 10; $i++) {
  MoveTo ($bar.Left + $bar.Width / 2) ($bar.Top + $bar.Height / 2); Pump 70
  MoveTo 100 400; Pump 470
  MoveTo ($bar.Left + $bar.Width / 2) ($bar.Top + $bar.Height / 2); Pump 50
  MoveTo 100 400; Pump 720
 }
 $afterGdi = [TestNative]::GetGuiResources($handle, 0)
 Assert ($afterGdi -gt 0 -and $afterGdi -le $gdi + 4) "Repeated open/close GDI resources stable ($gdi -> $afterGdi)"
 Assert ($bar.Idle -and $bar.Bounds -eq $anchor -and $bar.PresentCount -eq $arrowPresents) 'Rapid reversal leaves arrow stable and application idle'
 $bar.OpenManager(); Pump 300
 $manager = Field $bar 'manager'
 Assert ($manager.Visible -and $manager.FormBorderStyle -eq 'None') 'Modern borderless manager'
 $titleBox = Field (Field $manager 'title') 'Input'
 $dueBox = Field (Field $manager 'due') 'Input'
 $titleBox.Text = 'UI persistence test'; $dueBox.Text = 'not a date'
 InvokePrivate $manager 'SaveItem' @($null, [EventArgs]::Empty)
 Assert ([DesktopDDL.Store]::Data.Items.Count -eq 6) 'Invalid date rejected without writing'
 $dueBox.Text = [DateTime]::Now.AddDays(2).ToString('yyyy-MM-dd HH:mm')
 InvokePrivate $manager 'SaveItem' @($null, [EventArgs]::Empty)
 Assert ([DesktopDDL.Store]::Data.Items.Count -eq 7) 'Add item saves successfully'
 $titleBox.Text = 'Updated item'; InvokePrivate $manager 'SaveItem' @($null, [EventArgs]::Empty)
 Assert (@([DesktopDDL.Store]::Data.Items | Where-Object Title -eq 'Updated item').Count -eq 1) 'Edit item updates in place'
 InvokePrivate $manager 'ToggleDone' @($null, [EventArgs]::Empty)
 Assert ([DesktopDDL.Store]::Pending().Count -eq 5) 'Complete hides item from reminder'
 InvokePrivate $manager 'ToggleDone' @($null, [EventArgs]::Empty)
 Assert ([DesktopDDL.Store]::Pending().Count -eq 6) 'Restore brings item back'
 InvokePrivate $manager 'ChangeCount' @([int]1); Pump 550
 Assert ([DesktopDDL.Store]::Data.VisibleCount -eq 6) 'Custom stepper saves after debounce'
 Snapshot $manager 'preview-manager.png'
 $manager.Close(); Pump 100
 Assert ($null -eq (Field $bar 'manager')) 'Closed manager reference released'
 [DesktopDDL.Store]::Load()
 Assert ([DesktopDDL.Store]::Data.Items.Count -eq 7 -and [DesktopDDL.Store]::Data.VisibleCount -eq 6) 'Edits and settings survive reload'
 Write-Host 'All tests passed. User data untouched.'
} finally {
 $bar.Close(); $bar.Dispose(); [System.Windows.Forms.Cursor]::Position = $cursor
 if (Test-Path $sandbox) { Remove-Item -LiteralPath $sandbox -Recurse -Force }
}
