param([string]$Binary = 'DesktopDDL.exe')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing, System.Runtime.Serialization
$assembly = [Reflection.Assembly]::LoadFrom((Join-Path $PSScriptRoot $Binary))
Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing @'
using System;
using System.Diagnostics;
using System.Drawing;
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Windows.Forms;
public static class PerfProbe {
 [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
 [DllImport("user32.dll")] public static extern uint GetGuiResources(IntPtr h, uint flags);
 [MethodImpl(MethodImplOptions.NoInlining)]
 public static WeakReference Cycle(Form bar) {
  bar.GetType().GetMethod("OpenManager").Invoke(bar,new object[]{null}); Application.DoEvents();
  var manager=(Form)bar.GetType().GetField("manager",BindingFlags.NonPublic|BindingFlags.Instance).GetValue(bar);
  var reference=new WeakReference(manager); manager.Close(); Application.DoEvents(); return reference;
 }
 public static bool PartialPaintMatchesFull(Control list) {
  var flags=BindingFlags.NonPublic|BindingFlags.Instance;
  var paint=list.GetType().GetMethod("OnPaint",flags);
  var selection=list.GetType().GetField("SelectedId",flags);
  var items=(System.Collections.IList)list.GetType().GetField("Items",flags).GetValue(list);
  object previous=selection.GetValue(list);
  int row=(int)list.GetType().GetProperty("Row",flags).GetValue(list,null);
  try {
   selection.SetValue(list,null);
   using(var actual=new Bitmap(list.Width,list.Height)) using(var expected=new Bitmap(list.Width,list.Height))
   using(var a=Graphics.FromImage(actual)) using(var e=Graphics.FromImage(expected)) {
    paint.Invoke(list,new object[]{new PaintEventArgs(a,list.ClientRectangle)});
    selection.SetValue(list,items[0].GetType().GetField("Id").GetValue(items[0]));
    var clip=new Rectangle(0,0,list.Width,row);
    a.SetClip(clip);paint.Invoke(list,new object[]{new PaintEventArgs(a,clip)});a.ResetClip();
    paint.Invoke(list,new object[]{new PaintEventArgs(e,list.ClientRectangle)});
    for(int y=0;y<list.Height;y++) for(int x=0;x<list.Width;x++)
     if(actual.GetPixel(x,y)!=expected.GetPixel(x,y)) {
      Console.WriteLine("Partial repaint mismatch at "+x+","+y+": "+actual.GetPixel(x,y)+" vs "+expected.GetPixel(x,y));
      return false;
     }
    return true;
   }
  } finally {selection.SetValue(list,previous);}
 }
 public static string Bench(Control list) {
  AppDomain.MonitoringIsEnabled=true;
  var flags=BindingFlags.NonPublic|BindingFlags.Instance;
  var row=list.GetType().GetProperty("Row",flags);
  for(int i=0;i<100;i++) row.GetValue(list,null);
  long bytes=AppDomain.CurrentDomain.MonitoringTotalAllocatedMemorySize;
  var watch=Stopwatch.StartNew();
  for(int i=0;i<5000;i++) row.GetValue(list,null);
  watch.Stop();
  string result="5000 row queries: "+watch.Elapsed.TotalMilliseconds.ToString("F2")+" ms; allocated "+(AppDomain.CurrentDomain.MonitoringTotalAllocatedMemorySize-bytes)+" bytes\n";
  using(var bitmap=new Bitmap(list.Width,list.Height)) using(var g=Graphics.FromImage(bitmap)) {
   // Compare drawing only: exclude both the old framework buffer and the new owned buffer.
   var paint=list.GetType().GetMethod("PaintItems",flags);
   object[] args;
   if(paint!=null) args=new object[]{g,list.ClientRectangle};
   else {paint=list.GetType().GetMethod("OnPaint",flags);args=new object[]{new PaintEventArgs(g,list.ClientRectangle)};}
   for(int i=0;i<20;i++) paint.Invoke(list,args);
   bytes=AppDomain.CurrentDomain.MonitoringTotalAllocatedMemorySize;watch.Restart();
   for(int i=0;i<500;i++) paint.Invoke(list,args);
   watch.Stop();
   result+="500 full list draws: "+watch.Elapsed.TotalMilliseconds.ToString("F2")+" ms; allocated "+(AppDomain.CurrentDomain.MonitoringTotalAllocatedMemorySize-bytes)+" bytes\n";
   var clip=new Rectangle(0,0,list.Width,(int)row.GetValue(list,null));
   if(args.Length==2) args[1]=clip; else args[0]=new PaintEventArgs(g,clip);
   for(int i=0;i<20;i++) paint.Invoke(list,args);
   bytes=AppDomain.CurrentDomain.MonitoringTotalAllocatedMemorySize;watch.Restart();
   for(int i=0;i<500;i++) paint.Invoke(list,args);
   watch.Stop();
   result+="500 one-row invalidations: "+watch.Elapsed.TotalMilliseconds.ToString("F2")+" ms; allocated "+(AppDomain.CurrentDomain.MonitoringTotalAllocatedMemorySize-bytes)+" bytes";
  }
  return result;
 }
}
'@
[PerfProbe]::SetProcessDPIAware() | Out-Null
[Windows.Forms.Application]::EnableVisualStyles()
function Assert($condition, $message) { if (!$condition) { throw "FAIL: $message" }; Write-Host "PASS: $message" }
function Field($obj, $name) { $obj.GetType().GetField($name, [Reflection.BindingFlags]'NonPublic,Instance').GetValue($obj) }
function InvokePrivate($obj, $name, [object[]]$arguments) { return $obj.GetType().GetMethod($name, [Reflection.BindingFlags]'NonPublic,Instance').Invoke($obj, $arguments) }
function Pump([int]$ms) {
 $watch = [Diagnostics.Stopwatch]::StartNew()
 while ($watch.ElapsedMilliseconds -lt $ms) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 5 }
}
$sandbox = Join-Path $env:TEMP ('DesktopDDL-perf-' + [Guid]::NewGuid().ToString('N'))
[DesktopDDL.Store].GetField('Folder').SetValue($null, $sandbox)
[DesktopDDL.Store].GetField('FileName').SetValue($null, (Join-Path $sandbox 'reminders.json'))
[DesktopDDL.Store]::Data = New-Object DesktopDDL.Config
$now = [DateTime]::Now
for($i=0; $i -lt 40; $i++) {
 $item = New-Object DesktopDDL.Item; $item.Title = "Performance task $i"; $item.Due = $now.AddDays(10+$i)
 [DesktopDDL.Store]::Data.Items.Add($item)
}
$bar = $null; $cursor = [Windows.Forms.Cursor]::Position
try {
 [Windows.Forms.Cursor]::Position = New-Object Drawing.Point(100,400)
 $bar = New-Object DesktopDDL.ReminderBar; $bar.Show(); Pump 50
 $optimized = $null -ne $bar.GetType().GetProperty('PanelCacheBytes')
 InvokePrivate $bar 'SetStage' @([int]1); Pump 250
 if($optimized) {
  $single = $bar.PanelCacheBytes
  InvokePrivate $bar 'SetStage' @([int]2); Pump 250
  Write-Host "Panel cache: first=$single bytes; expanded=$($bar.PanelCacheBytes) bytes"
  Assert ($single * 4 -lt $bar.PanelCacheBytes) 'First-stage bitmap substantially smaller'
  $builds=$bar.CacheBuilds; $presents=$bar.PanelPresentCount
  [DesktopDDL.Store]::Data.Items[39].Title='Invisible change'
  [DesktopDDL.Store]::NotifyChanged()
  Assert ($bar.CacheBuilds -eq $builds -and $bar.PanelPresentCount -eq $presents) 'Invisible changes cause no render or present'
  [DesktopDDL.Store]::Data.Items[0].Requirements='Not displayed on the bar'
  [DesktopDDL.Store]::NotifyChanged()
  Assert ($bar.CacheBuilds -eq $builds) 'Requirements-only edit does not redraw cards'
  [DesktopDDL.Store]::Data.Items[0].Title='Visible change'
  [DesktopDDL.Store]::NotifyChanged()
  Assert ($bar.CacheBuilds -eq $builds+1) 'Visible title change redraws'
  # Simulated time avoids waiting for real minute/deadline boundaries.
  $fixed=[DateTime]::Today.AddHours(12)
  InvokePrivate $bar 'BuildCardsAt' @($fixed) | Out-Null
  $builds=$bar.CacheBuilds
  InvokePrivate $bar 'BuildCardsAt' @($fixed.AddSeconds(1)) | Out-Null
  Assert ($bar.CacheBuilds -eq $builds) 'Identical countdown text skips cache rebuilding'
  [DesktopDDL.Store]::Data.Items[0].Due=$fixed.AddDays(-1)
  [DesktopDDL.Store]::Data.Items[1].Due=$fixed.AddSeconds(2)
  [DesktopDDL.Store]::NotifyChanged()
  InvokePrivate $bar 'SetStage' @([int]1)
  $delay=InvokePrivate $bar 'NextRefreshDelay' @($fixed)
  Assert ($delay -gt 59000) 'Invisible imminent deadline does not wake first-stage clock'
  InvokePrivate $bar 'SetStage' @([int]2)
  $delay=InvokePrivate $bar 'NextRefreshDelay' @($fixed)
  Assert ($delay -ge 2000 -and $delay -lt 2100) 'Visible imminent deadline schedules refresh'
  InvokePrivate $bar 'BuildCardsAt' @($fixed.AddSeconds(1)) | Out-Null
  $builds=$bar.CacheBuilds
  InvokePrivate $bar 'BuildCardsAt' @($fixed.AddSeconds(3)) | Out-Null
  Assert ($bar.CacheBuilds -eq $builds+1) 'Deadline crossing refreshes overdue display'
 }
 InvokePrivate $bar 'SetStage' @([int]0); Pump 250
 if($optimized) { Assert ($bar.PanelCacheBytes -eq 0 -and $null -eq (Field $bar 'renderedCards')) 'Collapsed pixels and text snapshots released' }
 # Use identical data for baseline and optimized drawing benchmarks.
 for($i=0; $i -lt [DesktopDDL.Store]::Data.Items.Count; $i++) {
  [DesktopDDL.Store]::Data.Items[$i].Title="Performance task $i"
  [DesktopDDL.Store]::Data.Items[$i].Due=$now.AddDays(10+$i)
 }
 $bar.OpenManager(); Pump 100
 $manager = Field $bar 'manager'; $list = Field $manager 'list'
 Write-Host ([PerfProbe]::Bench($list))
 if($optimized) { Assert ([PerfProbe]::PartialPaintMatchesFull($list)) 'Partial selection repaint matches full repaint pixel-for-pixel' }
 $manager.Close(); Pump 100
 if($optimized) {
  Assert ($manager.IsDisposed -and $list.IsDisposed -and (Field $manager 'resourcesDisposed') -and (Field $list 'resourcesDisposed')) 'Manager and drawing resources explicitly disposed'
  Assert ((Field $list 'rowCache').Length -eq 0) 'Visible-row paths and date caches released on close'
 }
 $manager=$null; $list=$null
 $shared=[Drawing.BufferedGraphicsManager]::Current
 $size=Field $shared 'bufferSize'
 Write-Host "Shared buffer retained after close: $($size.Width*$size.Height*4) bytes"
 [PerfProbe]::Cycle($bar) | Out-Null
 $testProcess=[Diagnostics.Process]::GetCurrentProcess(); $handle=$testProcess.Handle
 $beforeGdi=[PerfProbe]::GetGuiResources($handle,0); $beforeUser=[PerfProbe]::GetGuiResources($handle,1)
 $refs=New-Object 'Collections.Generic.List[WeakReference]'
 for($i=0;$i -lt 20;$i++) { $refs.Add([PerfProbe]::Cycle($bar)) }
 $afterGdi=[PerfProbe]::GetGuiResources($handle,0); $afterUser=[PerfProbe]::GetGuiResources($handle,1)
 Assert ($null -eq (Field $bar 'manager')) 'Manager owner reference cleared'
 $resourceMessage="20 manager cycles: GDI $beforeGdi -> $afterGdi; USER $beforeUser -> $afterUser"
 Write-Host $resourceMessage
 Assert ($afterUser -le $beforeUser+4) 'USER resources stable before diagnostic collection'
 # Diagnostic-only collection in this disposable test host proves reachability.
 # Not used in the app or in the benchmarks/resource counts above.
 [GC]::Collect(); [GC]::WaitForPendingFinalizers(); [GC]::Collect()
 $alive=@($refs | Where-Object IsAlive).Count
 Assert ($alive -eq 0) 'All 20 closed manager objects are collectible (weak-reference test)'
 $collectedGdi=[PerfProbe]::GetGuiResources($handle,0)
 Write-Host "After diagnostic-only GC: GDI $collectedGdi; USER $([PerfProbe]::GetGuiResources($handle,1))"
 Assert ($collectedGdi -gt 0 -and $collectedGdi -le $beforeGdi+4) 'No permanent GDI growth after manager collection'
 [GC]::KeepAlive($testProcess)
 if($optimized) {
  [DesktopDDL.Store]::Data.Items.Clear(); [DesktopDDL.Store]::NotifyChanged()
  InvokePrivate $bar 'SetStage' @([int]1); Pump 250
  Assert (!(Field $bar 'clock').Enabled) 'Empty reminder has no refresh timer'
 }
 Write-Host "All performance checks passed: $Binary"
} finally {
 if($null -ne $bar) { $bar.Close(); $bar.Dispose() }
 [Windows.Forms.Cursor]::Position=$cursor
 if(Test-Path $sandbox) { Remove-Item -LiteralPath $sandbox -Recurse -Force }
}
