using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

namespace DesktopDDL
{
    internal static class Theme
    {
        internal static readonly Color Paper = Color.FromArgb(236, 239, 229);
        internal static readonly Color White = Color.FromArgb(249, 250, 245);
        internal static readonly Color Ink = Color.FromArgb(35, 44, 37);
        internal static readonly Color Green = Color.FromArgb(104, 123, 71);
        internal static readonly Color Muted = Color.FromArgb(127, 136, 122);
        internal static readonly Color Line = Color.FromArgb(211, 217, 201);
        internal static readonly Color Gold = Color.FromArgb(162, 156, 120);
        internal static readonly Color Red = Color.FromArgb(164, 72, 57);
        internal static GraphicsPath Round(Rectangle r, int radius)
        {
            var p = new GraphicsPath(); int d = Math.Min(radius * 2, Math.Min(r.Width, r.Height));
            if (d < 2) { p.AddRectangle(r); return p; }
            p.AddArc(r.Left, r.Top, d, d, 180, 90); p.AddArc(r.Right - d, r.Top, d, d, 270, 90);
            p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90); p.AddArc(r.Left, r.Bottom - d, d, d, 90, 90);
            p.CloseFigure(); return p;
        }
        internal static GraphicsPath CutCard(Rectangle r, int cut)
        {
            var p = new GraphicsPath(); p.AddPolygon(new Point[] { new Point(r.Left, r.Top), new Point(r.Right, r.Top),
                new Point(r.Right, r.Bottom - cut), new Point(r.Right - cut, r.Bottom), new Point(r.Left, r.Bottom) }); return p;
        }
        internal static void Text(Graphics g, string text, Font font, Rectangle box, Color color, bool centered = false)
        {
            TextRenderer.DrawText(g, text, font, box, color, TextFormatFlags.EndEllipsis | TextFormatFlags.SingleLine |
                TextFormatFlags.NoPrefix | TextFormatFlags.VerticalCenter | (centered ? TextFormatFlags.HorizontalCenter : TextFormatFlags.Left));
        }
    }
    internal sealed class FlatAction : Button
    {
        internal bool Primary, Danger;
        bool hover;
        public FlatAction()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            FlatStyle = FlatStyle.Flat; FlatAppearance.BorderSize = 0; Cursor = Cursors.Hand; UseVisualStyleBackColor = false;
        }
        protected override void OnMouseEnter(EventArgs e) { hover = true; Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { hover = false; Invalidate(); base.OnMouseLeave(e); }
        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics; g.Clear(Parent == null ? Theme.White : Parent.BackColor); g.SmoothingMode = SmoothingMode.AntiAlias;
            Color fill = Primary ? (hover ? Theme.Green : Theme.Ink) : hover ? Theme.Line : Theme.Paper;
            using (var path = Theme.Round(new Rectangle(0, 0, Width - 1, Height - 1), 6))
            using (var b = new SolidBrush(fill)) g.FillPath(b, path);
            Theme.Text(g, Text, Font, ClientRectangle, !Enabled ? Theme.Muted : Primary ? Theme.White : Danger ? Theme.Red : Theme.Ink, true);
            if (Focused && ShowFocusCues) ControlPaint.DrawFocusRectangle(g, Rectangle.Inflate(ClientRectangle, -4, -4));
        }
    }
    internal sealed class FieldBox : Panel
    {
        internal readonly TextBox Input = new TextBox();
        public FieldBox()
        {
            DoubleBuffered = true; BackColor = Theme.White;
            Input.BorderStyle = BorderStyle.None; Input.BackColor = Theme.White; Input.ForeColor = Theme.Ink;
            Input.Enter += delegate { Invalidate(); }; Input.Leave += delegate { Invalidate(); };
            Controls.Add(Input);
        }
        protected override void OnLayout(LayoutEventArgs e)
        {
            base.OnLayout(e);
            int pad = Input.Multiline ? Math.Max(10, Font.Height / 2) : Math.Max(10, Height / 4);
            Input.SetBounds(pad, Input.Multiline ? pad : Math.Max(0, (Height - Input.PreferredHeight) / 2),
                Math.Max(1, Width - 2 * pad), Input.Multiline ? Math.Max(1, Height - 2 * pad) : Input.PreferredHeight);
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e); e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            using (var path = Theme.Round(new Rectangle(0, 0, Width - 1, Height - 1), 6))
            using (var pen = new Pen(Input.Focused ? Theme.Green : Theme.Line)) e.Graphics.DrawPath(pen, path);
        }
    }
    internal sealed class ToggleSwitch : CheckBox
    {
        public ToggleSwitch()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer, true);
            Cursor = Cursors.Hand;
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics; g.Clear(BackColor); g.SmoothingMode = SmoothingMode.AntiAlias;
            int h = Math.Min(Height - 4, (int)(22 * g.DpiX / 96)), w = h * 2, y = (Height - h) / 2;
            using (var p = Theme.Round(new Rectangle(0, y, w, h), h / 2))
            using (var b = new SolidBrush(Checked ? Theme.Green : Theme.Line)) g.FillPath(b, p);
            g.FillEllipse(Brushes.White, Checked ? w - h + 3 : 3, y + 3, h - 6, h - 6);
            Theme.Text(g, Text, Font, new Rectangle(w + 10, 0, Width - w - 10, Height), Theme.Ink);
            if (Focused && ShowFocusCues) ControlPaint.DrawFocusRectangle(g, ClientRectangle);
        }
    }
    // Virtual, double-buffered list: paints only the rows on screen, no per-item controls.
    internal sealed class TaskList : Control
    {
        internal List<Item> Items = new List<Item>();
        internal event EventHandler SelectionChanged;
        internal string SelectedId;
        int offset, rowHeight = 82;
        float scale = 1;
        bool resourcesDisposed;
        readonly SolidBrush selectedBrush = new SolidBrush(Theme.Paper);
        readonly SolidBrush normalBrush = new SolidBrush(Color.FromArgb(244, 246, 239));
        readonly SolidBrush accentBrush = new SolidBrush(Theme.Green);
        readonly SolidBrush scrollBrush = new SolidBrush(Theme.Line);
        readonly SolidBrush backgroundBrush = new SolidBrush(Theme.White);
        sealed class RowCache
        {
            internal GraphicsPath Path;
            internal Rectangle Bounds;
            internal DateTime Due;
            internal string DateText;
        }
        RowCache[] rowCache = new RowCache[0];
        readonly Font heading = new Font("Microsoft YaHei UI", 10, FontStyle.Bold);
        readonly Font detail = new Font("Microsoft YaHei UI", 8.5f);
        internal TaskList()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw | ControlStyles.Selectable, true);
            TabStop = true; BackColor = Theme.White;
        }
        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            using (var g = CreateGraphics()) scale = g.DpiX / 96;
            int previousRow = rowHeight;
            rowHeight = Math.Max(1, (int)(82 * scale));
            offset = offset / previousRow * rowHeight;
            ClearRowCache();
        }
        void ClearRowCache()
        {
            foreach (var entry in rowCache) if (entry != null && entry.Path != null) entry.Path.Dispose();
            rowCache = new RowCache[0];
        }
        int Row { get { return rowHeight; } }
        protected override void OnSizeChanged(EventArgs e)
        {
            offset = Math.Min(offset, Math.Max(0, Items.Count * Row - Height));
            base.OnSizeChanged(e);
        }
        internal void UpdateItems(List<Item> items)
        {
            Items = items; offset = Math.Min(offset, Math.Max(0, Items.Count * Row - Height)); Invalidate();
        }
        internal void SelectId(string id)
        {
            string previous = SelectedId; int previousOffset = offset;
            SelectedId = id;
            int index = Items.FindIndex(x => x.Id == id), row = Row;
            if (index >= 0)
            {
                if (index * row < offset) offset = index * row;
                else if ((index + 1) * row > offset + Height) offset = Math.Max(0, (index + 1) * row - Height);
            }
            if (previousOffset != offset) Invalidate();
            else { InvalidateRow(previous); InvalidateRow(id); }
            var handler = SelectionChanged; if (handler != null) handler(this, EventArgs.Empty);
        }
        void InvalidateRow(string id)
        {
            int index = Items.FindIndex(x => x.Id == id);
            if (index >= 0) Invalidate(new Rectangle(0, index * Row - offset, Width, Row));
        }
        protected override void OnMouseDown(MouseEventArgs e)
        {
            base.OnMouseDown(e); Focus(); int index = (e.Y + offset) / Row;
            if (e.Button == MouseButtons.Left && index >= 0 && index < Items.Count) SelectId(Items[index].Id);
        }
        protected override void OnMouseWheel(MouseEventArgs e)
        {
            offset = Math.Max(0, Math.Min(Math.Max(0, Items.Count * Row - Height), offset - e.Delta / 120 * Row)); Invalidate(); base.OnMouseWheel(e);
        }
        protected override bool IsInputKey(Keys key) { return key == Keys.Up || key == Keys.Down || base.IsInputKey(key); }
        protected override void OnKeyDown(KeyEventArgs e)
        {
            if (Items.Count > 0 && (e.KeyCode == Keys.Up || e.KeyCode == Keys.Down))
            {
                int index = Items.FindIndex(x => x.Id == SelectedId); index = Math.Max(0, Math.Min(Items.Count - 1, index + (e.KeyCode == Keys.Down ? 1 : -1)));
                SelectId(Items[index].Id); e.Handled = true;
            }
            base.OnKeyDown(e);
        }
        protected override void OnPaintBackground(PaintEventArgs e) { }
        protected override void OnPaint(PaintEventArgs e)
        {
            if (resourcesDisposed || ClientSize.Width <= 0 || ClientSize.Height <= 0) return;
            PaintItems(e.Graphics, e.ClipRectangle);
            base.OnPaint(e);
        }
        void PaintItems(Graphics g, Rectangle clip)
        {
            // FillRectangle respects the clip; Graphics.Clear does not.
            // Clear with hard edges even when a Graphics instance is reused.
            g.SmoothingMode = SmoothingMode.None;
            g.FillRectangle(backgroundBrush, clip);
            float s = scale; int row = Row, pad = (int)(15 * s);
            g.SmoothingMode = SmoothingMode.AntiAlias;
            if (Items.Count == 0)
            {
                Theme.Text(g, "暂无事项", heading, new Rectangle(0, Height / 2 - (int)(30 * s), Width, (int)(32 * s)), Theme.Ink, true);
                Theme.Text(g, "在右侧写下你的第一个 DDL", detail, new Rectangle(0, Height / 2 + (int)(4 * s), Width, (int)(26 * s)), Theme.Muted, true);
                return;
            }
            int slots = Height / row + 2;
            if (rowCache.Length != slots) { ClearRowCache(); rowCache = new RowCache[slots]; }
            DateTime now = DateTime.Now;
            int end = Math.Min(Items.Count, (offset + clip.Bottom + row - 1) / row);
            for (int i = Math.Max(0, (offset + clip.Top) / row); i < end; i++)
            {
                Item item = Items[i]; int y = i * row - offset;
                int slot = i - offset / row;
                var cached = rowCache[slot];
                if (cached == null) rowCache[slot] = cached = new RowCache();
                var bounds = new Rectangle(0, y, Math.Max(1, Width - 8), Math.Max(1, row - (int)(8 * s)));
                if (cached.Path == null || cached.Bounds != bounds)
                {
                    if (cached.Path != null) cached.Path.Dispose();
                    cached.Bounds = bounds; cached.Path = Theme.Round(bounds, (int)(7 * s));
                }
                if (cached.DateText == null || cached.Due != item.Due)
                { cached.Due = item.Due; cached.DateText = item.Due.ToString("yyyy.MM.dd   HH:mm"); }
                g.FillPath(item.Id == SelectedId ? selectedBrush : normalBrush, cached.Path);
                if (item.Id == SelectedId) g.FillRectangle(accentBrush, 0, y + (int)(13 * s), (int)(3 * s), row - (int)(34 * s));
                Theme.Text(g, item.Title, heading, new Rectangle(pad, y + (int)(11 * s), Width - pad * 2 - (int)(62 * s), (int)(25 * s)), item.Done ? Theme.Muted : Theme.Ink);
                Theme.Text(g, cached.DateText, detail, new Rectangle(pad, y + (int)(40 * s), Width - pad * 2, (int)(22 * s)), Theme.Muted);
                bool late = !item.Done && item.Due < now;
                Theme.Text(g, item.Done ? "已完成" : late ? "逾期" : "待办", detail, new Rectangle(Width - (int)(75 * s), y + (int)(13 * s), (int)(60 * s), (int)(22 * s)), late ? Theme.Red : Theme.Green, true);
            }
            if (Items.Count * row > Height)
            {
                int h = Math.Max(20, Height * Height / (Items.Count * row)), y = offset * (Height - h) / Math.Max(1, Items.Count * row - Height);
                g.FillRectangle(scrollBrush, Width - 3, y, 3, h);
            }
        }
        protected override void Dispose(bool disposing)
        {
            if (!disposing || resourcesDisposed) { base.Dispose(disposing); return; }
            resourcesDisposed = true;
            try { base.Dispose(disposing); }
            finally
            {
                ClearRowCache();
                selectedBrush.Dispose(); normalBrush.Dispose(); accentBrush.Dispose(); scrollBrush.Dispose(); backgroundBrush.Dispose();
                heading.Dispose(); detail.Dispose(); Items.Clear(); SelectionChanged = null;
            }
        }
    }
}
