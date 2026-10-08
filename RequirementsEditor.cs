using System;
using System.Drawing;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows.Forms;

namespace DesktopDDL
{
    // Images are embedded in RTF; file links reference the original local files.
    internal sealed class RequirementsInput : RichTextBox
    {
        const int MaxRtfLength = 16 * 1024 * 1024;
        readonly ContextMenuStrip menu = new ContextMenuStrip();
        internal event Action<string> Failed;
        static readonly Regex FileUrls = new Regex(@"file://[^\s<>""\u0000]+", RegexOptions.IgnoreCase);
        [StructLayout(LayoutKind.Sequential)]
        struct TextRange { internal int Start, End; internal IntPtr Buffer; }
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        static extern IntPtr SendMessage(IntPtr window, int message, IntPtr parameter, ref TextRange range);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        static extern IntPtr SendMessage(IntPtr window, int message, IntPtr parameter, ref Point point);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        static extern IntPtr SendMessage(IntPtr window, int message, ref Point point, IntPtr parameter);
        public override int GetCharIndexFromPosition(Point point)
        {
            int index = (int)SendMessage(Handle, 0xD7, IntPtr.Zero, ref point);
            return Math.Max(0, Math.Min(TextLength, index));
        }
        public override Point GetPositionFromCharIndex(int index)
        {
            if (index < 0 || index > TextLength) return Point.Empty;
            var point = new Point();
            SendMessage(Handle, 0xD6, ref point, new IntPtr(index));
            return point;
        }
        string NativeText(int start, int end)
        {
            if (start < 0 || end <= start || end - start > 1024 * 1024) return "";
            var range = new TextRange { Start = start, End = end, Buffer = Marshal.AllocHGlobal((end - start + 1) * 2) };
            try
            {
                int length = (int)SendMessage(Handle, 0x44B, IntPtr.Zero, ref range); // EM_GETTEXTRANGE includes hidden targets.
                return length > 0 ? Marshal.PtrToStringUni(range.Buffer, length) : "";
            }
            finally { Marshal.FreeHGlobal(range.Buffer); }
        }
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
        static extern IntPtr LoadLibrary(string name);
        // The legacy RichEdit control silently drops PNG RTF. Windows 10/11 ship this newer control.
        // Keep its module loaded for the lifetime of all native editor windows.
        static readonly IntPtr RichEditModule = LoadLibrary("msftedit.dll");
        protected override CreateParams CreateParams
        {
            get
            {
                var value = base.CreateParams;
                if (RichEditModule != IntPtr.Zero) value.ClassName = "RICHEDIT50W";
                return value;
            }
        }
        public RequirementsInput()
        {
            BorderStyle = BorderStyle.None; BackColor = Theme.White; ForeColor = Theme.Ink;
            DetectUrls = true; EnableAutoDragDrop = false; HideSelection = false; AllowDrop = true;
            LinkClicked += OpenFileLink;
            DragEnter += delegate(object sender, DragEventArgs e)
            {
                e.Effect = e.Data.GetDataPresent(DataFormats.FileDrop) && (e.AllowedEffect & DragDropEffects.Copy) != 0
                    ? DragDropEffects.Copy : DragDropEffects.None;
            };
            DragDrop += delegate(object sender, DragEventArgs e)
            {
                try
                {
                    var paths = e.Data.GetData(DataFormats.FileDrop) as string[];
                    if (paths == null) return;
                    Select(GetCharIndexFromPosition(PointToClient(new Point(e.X, e.Y))), 0);
                    InsertFileLinks(paths);
                }
                catch (Exception ex) { Report(ex.Message); }
            };
            MaxLength = 10000; ScrollBars = RichTextBoxScrollBars.Vertical;
            AccessibleName = "事项说明，可输入文字、插入图片或粘贴截图";
            menu.Items.Add("剪切", null, delegate { Cut(); });
            menu.Items.Add("复制", null, delegate { Copy(); });
            menu.Items.Add("粘贴", null, delegate { PasteContent(); });
            menu.Items.Add("插入文件链接", null, delegate { ChooseFiles(); });
            menu.Items.Add("全选", null, delegate { SelectAll(); });
            ContextMenuStrip = menu;
        }
        internal void LoadContent(string text, string rtf)
        {
            Clear();
            if (string.IsNullOrEmpty(rtf)) Text = text ?? "";
            else
            {
                try { Rtf = rtf; }
                catch (ArgumentException) { Text = text ?? ""; Report("图文说明无法读取，已显示纯文字内容。"); }
            }
            UpgradeFileLinks();
            Select(0, 0); ClearUndo();
        }
        internal string SavedRtf() { return TextLength == 0 ? "" : Rtf; }
        internal void InsertImageFile(string path)
        {
            if (new FileInfo(path).Length > 20 * 1024 * 1024)
                throw new InvalidOperationException("图片文件不能超过 20 MB。");
            using (var image = Image.FromFile(path)) InsertImage(image);
        }
        internal void InsertImage(Image image)
        {
            if (RichEditModule == IntPtr.Zero)
                throw new InvalidOperationException("系统图文编辑组件不可用，无法插入图片。");
            if ((long)image.Width * image.Height > 24000000)
                throw new InvalidOperationException("图片不能超过 2400 万像素，请先缩小图片。");
            double ratio = Math.Min(1, 1600.0 / Math.Max(image.Width, image.Height));
            int width = Math.Max(1, (int)(image.Width * ratio)), height = Math.Max(1, (int)(image.Height * ratio));
            byte[] bytes;
            using (var bitmap = new Bitmap(width, height))
            {
                using (var g = Graphics.FromImage(bitmap))
                {
                    g.Clear(Color.White); g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                    g.DrawImage(image, new Rectangle(0, 0, width, height));
                }
                using (var stream = new MemoryStream())
                {
                    bitmap.Save(stream, ImageFormat.Png); bytes = stream.ToArray();
                }
            }
            if (bytes.Length > 3 * 1024 * 1024)
                throw new InvalidOperationException("图片压缩后仍超过 3 MB，请先缩小图片。");
            if ((long)Rtf.Length + bytes.Length * 2 + 256 > MaxRtfLength)
                throw new InvalidOperationException("此事项的图片过多，请删除部分图片后重试。");
            // RTF uses twips (1/1440 inch); keep inserted pictures readable within the editor.
            double display = Math.Min(1, Math.Min(260.0 / width, 180.0 / height));
            var rtf = new StringBuilder(bytes.Length * 2 + 256);
            rtf.Append(@"{\rtf1\ansi{\pict\pngblip\picw").Append(width).Append(@"\pich").Append(height);
            rtf.Append(@"\picwgoal").Append((int)(width * display * 15));
            rtf.Append(@"\pichgoal").Append((int)(height * display * 15)).Append(' ');
            const string hex = "0123456789abcdef";
            foreach (byte b in bytes) { rtf.Append(hex[b >> 4]); rtf.Append(hex[b & 15]); }
            rtf.Append("}}");
            SelectedRtf = rtf.ToString(); Focus(); ScrollToCaret();
        }
        void ChooseFiles()
        {
            using (var dialog = new OpenFileDialog { Multiselect = true, CheckFileExists = true })
            {
                if (dialog.ShowDialog(FindForm()) != DialogResult.OK) return;
                try { InsertFileLinks(dialog.FileNames); }
                catch (Exception ex) { Report(ex.Message); }
            }
        }
        internal void InsertFileLinks(string[] paths)
        {
            if (paths == null || paths.Length == 0) return;
            var links = new List<string>();
            foreach (string path in paths)
            {
                string fullPath = Path.GetFullPath(path);
                if (!File.Exists(fullPath)) throw new FileNotFoundException("文件不存在：" + fullPath);
                links.Add(new Uri(fullPath).AbsoluteUri);
            }
            string previous = SelectionStart > 0 ? NativeText(SelectionStart - 1, SelectionStart) : "";
            string text = (previous != "" && previous != "\r" && previous != "\n" ? "\n" : "") +
                string.Join("\n", links.ToArray()) + "\n";
            InsertLinkedText(text); Focus(); ScrollToCaret();
        }
        static bool TryFileUri(string value, out Uri uri)
        {
            return Uri.TryCreate(value, UriKind.Absolute, out uri) && uri.IsFile &&
                string.IsNullOrEmpty(uri.Query) && string.IsNullOrEmpty(uri.Fragment) &&
                !string.IsNullOrEmpty(Path.GetFileName(uri.LocalPath));
        }
        static string EscapeRtf(string text)
        {
            var result = new StringBuilder();
            foreach (char c in text)
            {
                if (c == '\\' || c == '{' || c == '}') result.Append('\\').Append(c);
                else if (c == '\n') result.Append(@"\par ");
                else if (c == '\r') continue;
                else if (c > 127) result.Append(@"\u").Append(unchecked((short)c)).Append('?');
                else result.Append(c);
            }
            return result.ToString();
        }
        static string FileField(Uri uri)
        {
            // LocalPath decodes percent escapes once; keep the encoded target separate from its visible filename.
            return @"{\field{\*\fldinst{HYPERLINK """ + EscapeRtf(uri.AbsoluteUri) +
                @"""}}{\fldrslt{\ul " + EscapeRtf(Path.GetFileName(uri.LocalPath)) + "}}}";
        }
        void InsertLinkedText(string text)
        {
            if (TextLength - SelectionLength + text.Length > MaxLength)
                throw new InvalidOperationException("说明文字不能超过 10000 字。");
            var rtf = new StringBuilder(@"{\rtf1\ansi\uc1 ");
            int offset = 0;
            foreach (Match match in FileUrls.Matches(text))
            {
                Uri uri;
                rtf.Append(EscapeRtf(text.Substring(offset, match.Index - offset)));
                rtf.Append(TryFileUri(match.Value, out uri) ? FileField(uri) : EscapeRtf(match.Value));
                offset = match.Index + match.Length;
            }
            rtf.Append(EscapeRtf(text.Substring(offset))).Append('}');
            if ((long)Rtf.Length + rtf.Length > MaxRtfLength)
                throw new InvalidOperationException("此事项的内容过多。");
            SelectedRtf = rtf.ToString();
        }
        void UpgradeFileLinks()
        {
            // Use native positions: friendly links contain hidden field instructions, so Text indexes differ.
            var matches = FileUrls.Matches(NativeText(0, TextLength));
            for (int i = matches.Count - 1; i >= 0; i--)
            {
                var match = matches[i]; Uri uri;
                if (!TryFileUri(match.Value, out uri)) continue;
                Select(match.Index, match.Length);
                if (SelectedText != match.Value) continue; // Never rewrite an existing field's hidden target.
                SelectedRtf = @"{\rtf1\ansi\uc1 " + FileField(uri) + "}";
            }
        }
        internal static string ResolveFileLink(string link)
        {
            Uri uri;
            if (!Uri.TryCreate(link, UriKind.Absolute, out uri) || !uri.IsFile ||
                !string.IsNullOrEmpty(uri.Query) || !string.IsNullOrEmpty(uri.Fragment))
                throw new InvalidOperationException("无效的文件链接。");
            string path = uri.LocalPath;
            if (!File.Exists(path)) throw new FileNotFoundException("文件不存在：" + path);
            return path;
        }
        void OpenFileLink(object sender, LinkClickedEventArgs e)
        {
            try { Process.Start(new ProcessStartInfo(ResolveFileLink(e.LinkText)) { UseShellExecute = true }); }
            catch (Exception ex) { Report(ex.Message); }
        }
        void Report(string message) { var handler = Failed; if (handler != null) handler(message); }
        internal void PasteContent()
        {
            try
            {
                if (Clipboard.ContainsFileDropList())
                {
                    var files = Clipboard.GetFileDropList();
                    var paths = new string[files.Count]; files.CopyTo(paths, 0);
                    InsertFileLinks(paths);
                }
                else if (Clipboard.ContainsImage())
                {
                    using (var image = Clipboard.GetImage()) if (image != null) InsertImage(image);
                }
                else if (Clipboard.ContainsText())
                {
                    string text = Clipboard.GetText();
                    string path = text.Trim().Trim('"');
                    if (((path.Length >= 3 && path[1] == ':' && (path[2] == '\\' || path[2] == '/')) ||
                        path.StartsWith(@"\\")) && File.Exists(path))
                    { InsertFileLinks(new string[] { path }); return; }
                    if (TextLength - SelectionLength + text.Length > MaxLength)
                        throw new InvalidOperationException("说明文字不能超过 10000 字。");
                    InsertLinkedText(text);
                }
            }
            catch (Exception ex) { Report("粘贴失败：" + ex.Message); }
        }
        protected override bool ProcessCmdKey(ref Message msg, Keys keyData)
        {
            if (keyData == (Keys.Control | Keys.V) || keyData == (Keys.Shift | Keys.Insert))
            { PasteContent(); return true; }
            return base.ProcessCmdKey(ref msg, keyData);
        }
        protected override void WndProc(ref Message m)
        {
            if (m.Msg == 0x302) { PasteContent(); return; } // WM_PASTE, including programmatic Paste().
            // .NET Framework drops EN_LINK events when hidden targets extend past Text.Length.
            // RichEdit packs ENLINK at 4-byte alignment after its native NMHDR on both architectures.
            if (m.Msg == 0x204E && m.LParam != IntPtr.Zero && Marshal.ReadInt32(m.LParam, IntPtr.Size * 2) == 0x70B)
            {
                int header = IntPtr.Size == 8 ? 24 : 12;
                int message = Marshal.ReadInt32(m.LParam, header);
                if (message == 0x201 || (message == 0x100 && Marshal.ReadIntPtr(m.LParam, header + 4).ToInt64() == 13))
                {
                    int rangeOffset = header + 4 + IntPtr.Size * 2;
                    string link = NativeText(Marshal.ReadInt32(m.LParam, rangeOffset), Marshal.ReadInt32(m.LParam, rangeOffset + 4));
                    var target = Regex.Match(link, "HYPERLINK\\s+\\\"([^\\\"]+)\\\"", RegexOptions.IgnoreCase);
                    if (target.Success) link = target.Groups[1].Value;
                    if (!string.IsNullOrEmpty(link)) OnLinkClicked(new LinkClickedEventArgs(link));
                    m.Result = new IntPtr(1); return;
                }
            }
            base.WndProc(ref m);
        }
        protected override void Dispose(bool disposing)
        {
            if (disposing) menu.Dispose();
            base.Dispose(disposing);
        }
    }
    internal sealed class RequirementsBox : Panel
    {
        internal readonly RequirementsInput Input = new RequirementsInput();
        public RequirementsBox()
        {
            DoubleBuffered = true; BackColor = Theme.White;
            Input.Enter += delegate { Invalidate(); }; Input.Leave += delegate { Invalidate(); };
            Controls.Add(Input);
        }
        protected override void OnLayout(LayoutEventArgs e)
        {
            base.OnLayout(e);
            int pad = Math.Max(8, Font.Height / 2);
            Input.SetBounds(pad, pad, Math.Max(1, Width - 2 * pad), Math.Max(1, Height - 2 * pad));
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e); e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            using (var path = Theme.Round(new Rectangle(0, 0, Width - 1, Height - 1), 6))
            using (var pen = new Pen(Input.Focused ? Theme.Green : Theme.Line)) e.Graphics.DrawPath(pen, path);
        }
    }
}
