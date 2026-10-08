param([string]$Binary = 'DesktopDDL.exe', [switch]$TestClipboard)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing, System.Runtime.Serialization
[System.Reflection.Assembly]::LoadFrom((Join-Path $PSScriptRoot $Binary)) | Out-Null
function Assert($condition, $message) { if (!$condition) { throw "FAIL: $message" }; Write-Host "PASS: $message" }
function Field($obj, $name) { $obj.GetType().GetField($name, [System.Reflection.BindingFlags]'NonPublic,Instance').GetValue($obj) }
function InvokePrivate($obj, $name, [object[]]$arguments) {
    $obj.GetType().GetMethod($name, [System.Reflection.BindingFlags]'NonPublic,Instance').Invoke($obj, $arguments) | Out-Null
}
$sandbox = Join-Path $env:TEMP ('DesktopDDL-requirements-' + [Guid]::NewGuid().ToString('N'))
[DesktopDDL.Store].GetField('Folder').SetValue($null, $sandbox)
[DesktopDDL.Store].GetField('FileName').SetValue($null, (Join-Path $sandbox 'reminders.json'))
$manager = $null
try {
    Assert ([DesktopDDL.Store]::FileName.StartsWith($sandbox)) 'Test data isolated'
    New-Item -ItemType Directory -Path $sandbox | Out-Null
    # A pre-feature file without the Requirements member must remain readable.
    [IO.File]::WriteAllText([DesktopDDL.Store]::FileName, '{"VisibleCount":5,"Items":[{"Id":"legacy","Title":"Old task","Due":"\/Date(1791446400000)\/","Done":false}]}')
    [DesktopDDL.Store]::Load()
    Assert ($null -eq [DesktopDDL.Store]::Warning -and [DesktopDDL.Store]::Data.Items[0].Requirements -eq '') 'Legacy requirements default to empty'
    $manager = New-Object DesktopDDL.Manager
    Assert ($null -eq $manager.GetType().GetField('insertImage', [Reflection.BindingFlags]'NonPublic,Instance')) 'Insert-image button removed'
    $requirements = Field $manager 'requirements'
    $input = Field $requirements 'Input'
    $title = Field (Field $manager 'title') 'Input'
    $due = Field (Field $manager 'due') 'Input'
    Assert ($input.Multiline -and $input -is [System.Windows.Forms.RichTextBox] -and $input.Height -gt 40) 'Rich text editor has usable height'
    Assert ($requirements.Bottom -lt (Field $manager 'save').Top) 'Requirements do not overlap save button'
    $manager.SelectItem('legacy')
    Assert ($input.Text -eq '') 'Legacy item opens with blank requirements'
    InvokePrivate $manager 'NewItem' @()
    $title.Text = 'Requirements test'; $due.Text = '2027-10-08 18:30'
    $value = "First requirement`nSecond requirement"
    $input.Text = $value
    InvokePrivate $manager 'SaveItem' @($null, [EventArgs]::Empty)
    $item = [DesktopDDL.Store]::Data.Items[1]; $id = $item.Id
    Assert ($item.Requirements -eq $value) 'New item saves multiline requirements'
    [DesktopDDL.Store]::Load(); $manager.SelectItem($id)
    Assert ($input.Text -eq $value) 'Requirements survive JSON reload and selection'
    $input.Text = 'Updated requirement'
    InvokePrivate $manager 'SaveItem' @($null, [EventArgs]::Empty)
    [DesktopDDL.Store]::Load()
    Assert ([DesktopDDL.Store]::Data.Items[1].Requirements -eq 'Updated requirement') 'Existing requirements can be edited'
    InvokePrivate $manager 'NewItem' @()
    Assert ($input.Text -eq '') 'New item clears previous requirements'
    $manager.SelectItem($id); $input.Clear()
    InvokePrivate $manager 'SaveItem' @($null, [EventArgs]::Empty)
    [DesktopDDL.Store]::Load()
    Assert ([DesktopDDL.Store]::Data.Items[1].Requirements -eq '') 'Requirements are optional and can be cleared'
    Assert ([DesktopDDL.Store]::Data.Items[0].RequirementsRtf -eq '') 'Legacy rich content defaults to empty'
    Assert ([DesktopDDL.Store]::Data.Items[1].RequirementsRtf -eq '') 'Clearing removes rich content too'
    $manager.SelectItem($id)
    $input.Text = 'Before image'; $input.Select($input.TextLength, 0)
    $path = Join-Path $sandbox 'sample.png'
    $bitmap = New-Object System.Drawing.Bitmap(120, 80)
    try {
        $g = [System.Drawing.Graphics]::FromImage($bitmap)
        try { $g.Clear([System.Drawing.Color]::OrangeRed) } finally { $g.Dispose() }
        $bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally { $bitmap.Dispose() }
    InvokePrivate $input 'InsertImageFile' @([string]$path)
    Remove-Item -LiteralPath $path
    Assert ($input.Rtf.Contains('\pict')) 'File image embedded without keeping source file locked'
    $input.SelectedText = 'After image'
    InvokePrivate $manager 'SaveItem' @($null, [EventArgs]::Empty)
    [DesktopDDL.Store]::Load()
    $saved = [DesktopDDL.Store]::Data.Items[1].RequirementsRtf
    Assert ($saved.Contains('\pict')) 'Embedded image persisted in JSON'
    $manager.Dispose(); $manager = New-Object DesktopDDL.Manager
    $input = Field (Field $manager 'requirements') 'Input'
    $manager.SelectItem($id)
    Assert ($input.Rtf.Contains('\pict') -and $input.Text.Contains('Before image') -and $input.Text.Contains('After image')) 'Text and image survive closing editor and JSON reload'
    InvokePrivate $manager 'NewItem' @()
    Assert (!$input.Rtf.Contains('\pict') -and $input.TextLength -eq 0) 'New item has no previous images'
    $manager.SelectItem($id)
    $input.Select('Before image'.Length, 1); $input.SelectedText = ''
    Assert ($input.Text -eq 'Before imageAfter image') 'Deleting only the image preserves surrounding text'
    InvokePrivate $manager 'SaveItem' @($null, [EventArgs]::Empty)
    [DesktopDDL.Store]::Load()
    Assert (![DesktopDDL.Store]::Data.Items[1].RequirementsRtf.Contains('\pict')) 'Selected image can be deleted and removal persists'
    $path = Join-Path $sandbox 'invalid.png'; [IO.File]::WriteAllText($path, 'not an image')
    $before = $input.Rtf; $rejected = $false
    try { InvokePrivate $input 'InsertImageFile' @([string]$path) } catch { $rejected = $true }
    Assert ($rejected -and $input.Rtf -eq $before) 'Invalid image does not change editor content'
    $large = Join-Path $sandbox 'large.png'
    $stream = [IO.File]::Create($large)
    try { $stream.SetLength(21 * 1024 * 1024) } finally { $stream.Dispose() }
    $rejected = $false
    try { InvokePrivate $input 'InsertImageFile' @([string]$large) } catch { $rejected = $true }
    Assert ($rejected -and $input.Rtf -eq $before) 'Oversized file rejected without changing content'
    if ($TestClipboard) {
        # Opt-in: snapshot clipboard data before testing the normal paste route.
        $original = [Windows.Forms.Clipboard]::GetDataObject()
        $copy = New-Object Windows.Forms.DataObject
        if ($null -ne $original) {
            foreach ($format in $original.GetFormats($false)) {
                $copy.SetData($format, $false, $original.GetData($format, $false))
            }
        }
        $bitmap = New-Object Drawing.Bitmap(60, 40)
        try {
            [Windows.Forms.Clipboard]::SetImage($bitmap)
            $input.Clear(); $input.Paste()
            Assert ($input.Rtf.Contains('\pict') -and $input.TextLength -eq 1) 'Clipboard image pastes through WM_PASTE'
            Assert ($input.CanUndo) 'Image insertion supports undo'
            $input.Undo()
            Assert (!$input.Rtf.Contains('\pict')) 'Undo removes inserted image'
            [Windows.Forms.Clipboard]::SetText('Pasted text')
            $input.Clear(); $input.Paste()
            Assert ($input.Text -eq 'Pasted text') 'Plain-text paste still works'
        } finally {
            $bitmap.Dispose()
            if ($null -eq $original) { [Windows.Forms.Clipboard]::Clear() }
            else { [Windows.Forms.Clipboard]::SetDataObject($copy, $true) }
        }
    }
    Write-Host 'All requirements tests passed. User data untouched.'
} finally {
    if ($null -ne $manager) { $manager.Dispose() }
    if (Test-Path $sandbox) { Remove-Item -LiteralPath $sandbox -Recurse -Force }
}
