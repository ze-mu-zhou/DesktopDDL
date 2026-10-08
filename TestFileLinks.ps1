param([string]$Binary = 'DesktopDDL.exe', [switch]$TestClipboard)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing, System.Runtime.Serialization
[Reflection.Assembly]::LoadFrom((Join-Path $PSScriptRoot $Binary)) | Out-Null
Add-Type -ReferencedAssemblies System.Windows.Forms,System.Drawing @'
using System;
using System.Drawing;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Windows.Forms;
public static class LinkProbe {
 [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
 struct Format {
  public uint size, mask, effects;
  public int height, offset;
  public uint color;
  public byte charset, pitch;
  [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string face;
 }
 [DllImport("user32.dll", CharSet=CharSet.Unicode)]
 static extern IntPtr SendMessage(IntPtr h, int m, IntPtr w, ref Format f);
 [DllImport("user32.dll", CharSet=CharSet.Unicode)]
 static extern IntPtr SendMessage(IntPtr h, int m, IntPtr w, IntPtr l);
 public static bool IsLink(RichTextBox input) {
  var f = new Format(); f.size=(uint)Marshal.SizeOf(typeof(Format));
  SendMessage(input.Handle, 0x43A, new IntPtr(1), ref f);
  return (f.effects & 0x20) != 0;
 }
 public static string Click(RichTextBox input, int index) {
  // Exercise real native EN_LINK notifications without launching any application.
  var method=input.GetType().GetMethod("OpenFileLink",BindingFlags.NonPublic|BindingFlags.Instance);
  var open=(LinkClickedEventHandler)Delegate.CreateDelegate(typeof(LinkClickedEventHandler),input,method);
  string target=null;
  LinkClickedEventHandler capture=delegate(object sender,LinkClickedEventArgs e) { target=e.LinkText; };
  input.LinkClicked-=open; input.LinkClicked+=capture;
  try {
   input.Select(index,0); input.ScrollToCaret(); input.Focus(); Application.DoEvents();
   Point p=input.GetPositionFromCharIndex(index); p.Offset(3,input.Font.Height/2);
   IntPtr position=new IntPtr((p.Y << 16) | (p.X & 0xffff));
   SendMessage(input.Handle,0x200,IntPtr.Zero,position);
   SendMessage(input.Handle,0x201,new IntPtr(1),position);
   SendMessage(input.Handle,0x202,IntPtr.Zero,position);
   Application.DoEvents(); return target;
  } finally { input.LinkClicked-=capture; input.LinkClicked+=open; }
 }
}
'@
function Assert($condition, $message) { if (!$condition) { throw "FAIL: $message" }; Write-Host "PASS: $message" }
$flags = [Reflection.BindingFlags]'NonPublic,Instance'
function Field($obj, $name) { $obj.GetType().GetField($name, $flags).GetValue($obj) }
function Call($obj, $name, [object[]]$arguments) { $obj.GetType().GetMethod($name, $flags).Invoke($obj, $arguments) }
$sandbox = Join-Path $env:TEMP ('DesktopDDL-links-' + [Guid]::NewGuid().ToString('N'))
[DesktopDDL.Store].GetField('Folder').SetValue($null, $sandbox)
[DesktopDDL.Store].GetField('FileName').SetValue($null, (Join-Path $sandbox 'reminders.json'))
$manager = $null
try {
    New-Item -ItemType Directory -Path $sandbox | Out-Null
    [DesktopDDL.Store]::Data = New-Object DesktopDDL.Config
    $manager = New-Object DesktopDDL.Manager; $manager.Show()
    $input = Field (Field $manager 'requirements') 'Input'
    $title = Field (Field $manager 'title') 'Input'; $title.Text = 'File links'
    $name = [string][char]0x6587 + ' space # %20 {x}.txt'
    $path = Join-Path $sandbox $name
    [IO.File]::WriteAllText($path, 'test')
    $uri = ([Uri]$path).AbsoluteUri
    $arguments = New-Object object[] 1; $arguments[0] = [string[]]@($path)
    $input.Text = 'Before'; $input.Select($input.TextLength, 0)
    Call $input 'InsertFileLinks' $arguments
    Assert ($input.Text -eq "Before`n$name`n") 'Only decoded filename is displayed; target stays hidden'
    Assert ($input.Rtf.Contains('HYPERLINK') -and $input.Rtf.Contains($uri)) 'Original encoded target stored separately in RTF'
    $index = $input.Find($name)
    Assert ([LinkProbe]::IsLink($input)) 'Filename is a real native hyperlink'
    Assert ([LinkProbe]::Click($input, $index) -eq $uri) 'Clicking filename emits exact target URL'
    $resolve = $input.GetType().GetMethod('ResolveFileLink', [Reflection.BindingFlags]'NonPublic,Static')
    Assert ($resolve.Invoke($null, [object[]]@([string]$uri)) -eq $path) 'Chinese, spaces, percent, hash and braces decode exactly once'
    Call $manager 'SaveItem' @($null, [EventArgs]::Empty)
    $id = [DesktopDDL.Store]::Data.Items[0].Id
    $manager.Dispose(); $manager = $null
    [DesktopDDL.Store]::Load()
    $manager = New-Object DesktopDDL.Manager; $manager.SelectItem($id); $manager.Show()
    $input = Field (Field $manager 'requirements') 'Input'
    Assert ($input.Text -eq "Before`n$name`n") 'Filename-only display survives save and reopen'
    $index = $input.Find($name)
    Assert ([LinkProbe]::IsLink($input)) 'Reopened filename remains clickable'
    Assert ([LinkProbe]::Click($input, $index) -eq $uri) 'Reopened filename click retains correct target'
    Assert (([regex]::Matches($input.Rtf, 'HYPERLINK')).Count -eq 1) 'Loading does not nest or duplicate named links'
    $input.Find($name) | Out-Null; $input.SelectedText = ''
    Call $manager 'SaveItem' @($null, [EventArgs]::Empty); [DesktopDDL.Store]::Load()
    Assert (![DesktopDDL.Store]::Data.Items[0].RequirementsRtf.Contains($uri)) 'Deleting filename removes its hidden link'
    Assert (Test-Path -LiteralPath $path) 'Deleting link does not delete original file'
    Call $input 'LoadContent' @([string]"Before`n$uri`nAfter", '')
    Assert ($input.Text -eq "Before`n$name`nAfter") 'Legacy plain URL becomes filename without changing surrounding text'
    $named = $input.Rtf
    Call $input 'LoadContent' @('', [string]$named)
    Assert ($input.Text -eq "Before`n$name`nAfter") 'Named links are stable across repeated loading'
    $input.Text = "Before`n$uri`nAfter"; $legacyRtf = $input.Rtf
    Call $input 'LoadContent' @('', [string]$legacyRtf)
    Assert ($input.Text -eq "Before`n$name`nAfter") 'Legacy RTF URLs also migrate'
    # Duplicate labels must resolve by the clicked field, never by filename lookup.
    $otherFolder = Join-Path $sandbox 'other'; New-Item -ItemType Directory -Path $otherFolder | Out-Null
    $otherPath = Join-Path $otherFolder $name; [IO.File]::WriteAllText($otherPath, 'other')
    $otherUri = ([Uri]$otherPath).AbsoluteUri
    $input.Select($input.TextLength, 0)
    $arguments[0] = [string[]]@($otherPath); Call $input 'InsertFileLinks' $arguments
    $first = $input.Find($name); $second = $input.Find($name, $first + $name.Length, [Windows.Forms.RichTextBoxFinds]::None)
    Assert ($second -gt $first -and [LinkProbe]::Click($input, $second) -eq $otherUri) 'Identical filenames retain independent target paths'
    $mixed = $input.Rtf; Call $input 'LoadContent' @('', [string]$mixed)
    Assert (([regex]::Matches($input.Rtf, 'HYPERLINK')).Count -eq 2) 'Multiple named links survive reload without target corruption'
    Remove-Item -LiteralPath $path
    Call $input 'LoadContent' @([string]$uri, '')
    Assert ($input.Text -eq $name) 'Missing original file still displays its filename'
    $rejected = $false
    try { $resolve.Invoke($null, [object[]]@([string]$uri)) } catch { $rejected = $true }
    Assert ($rejected) 'Missing linked file is rejected when opening'
    [IO.File]::WriteAllText($path, 'test')
    if ($TestClipboard) {
        $original = [Windows.Forms.Clipboard]::GetDataObject()
        $copy = New-Object Windows.Forms.DataObject
        if ($null -ne $original) {
            foreach ($format in $original.GetFormats($false)) { $copy.SetData($format, $false, $original.GetData($format, $false)) }
        }
        try {
            $files = New-Object Collections.Specialized.StringCollection; $files.Add($path) | Out-Null
            [Windows.Forms.Clipboard]::SetFileDropList($files)
            $input.Clear(); $input.Paste()
            Assert ($input.Text.Trim() -eq $name) 'Copied file pastes as filename'
            [Windows.Forms.Clipboard]::SetText('"' + $path + '"')
            $input.Clear(); $input.Paste()
            Assert ($input.Text.Trim() -eq $name) 'Copied file path pastes as filename'
            [Windows.Forms.Clipboard]::SetText($uri)
            $input.Clear(); $input.Paste()
            Assert ($input.Text -eq $name -and $input.Rtf.Contains($uri)) 'Pasted encoded URL becomes filename with original target'
            [Windows.Forms.Clipboard]::SetText("one`r`ntwo")
            $input.Clear(); $input.Paste()
            Assert ($input.Text -eq "one`ntwo") 'Multiline text paste is unchanged'
        } finally {
            if ($null -eq $original) { [Windows.Forms.Clipboard]::Clear() }
            else { [Windows.Forms.Clipboard]::SetDataObject($copy, $true) }
        }
    }
    $rejected = $false
    try { $resolve.Invoke($null, [object[]]@('https://example.com')) } catch { $rejected = $true }
    Assert ($rejected) 'Non-file schemes cannot launch through file handler'
    Write-Host 'All file-link tests passed. User data untouched.'
} finally {
    if ($null -ne $manager) { $manager.Dispose() }
    if (Test-Path $sandbox) { Remove-Item -LiteralPath $sandbox -Recurse -Force }
}
