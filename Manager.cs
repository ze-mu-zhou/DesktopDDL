using System;
using System.Drawing;
using System.Linq;
using System.Globalization;
using System.Windows.Forms;
using Microsoft.Win32;

namespace DesktopDDL
{
    public sealed class Manager : Form
    {
        readonly TaskList list = new TaskList();
        readonly FieldBox title = new FieldBox(), due = new FieldBox();
        readonly RequirementsBox requirements = new RequirementsBox();
        readonly FlatAction close = new FlatAction { Text = "×", AccessibleName = "关闭管理窗口" };
        readonly FlatAction add = new FlatAction { Text = "+ 新建事项" };
        readonly FlatAction save = new FlatAction { Text = "添加事项", Primary = true };
        readonly FlatAction complete = new FlatAction { Text = "标记完成" };
        readonly FlatAction delete = new FlatAction { Text = "删除", Danger = true };
        readonly FlatAction less = new FlatAction { Text = "−", AccessibleName = "减少展开数量" }, more = new FlatAction { Text = "+", AccessibleName = "增加展开数量" };
        readonly ToggleSwitch startup = new ToggleSwitch { Text = "登录 Windows 时启动" };
        readonly Timer countSave = new Timer { Interval = 450 };
        readonly Icon appIcon = AppIcons.ApplicationIcon();
        readonly Font uiFont = new Font("Microsoft YaHei UI", 9.5f);
        readonly Font heading = new Font("Microsoft YaHei UI", 23, FontStyle.Bold);
        readonly Font small = new Font("Microsoft YaHei UI", 8.5f);
        readonly Font code = new Font("Consolas", 9, FontStyle.Bold);
        readonly Font number = new Font("Consolas", 15, FontStyle.Bold);
        readonly float scale;
        bool ready, countDirty, error, resourcesDisposed;
        int pendingCount;
        string selectedId, message = "";
        const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
        public Manager()
        {
            using (var g = Graphics.FromHwnd(IntPtr.Zero)) scale = g.DpiX / 96;
            AutoScaleMode = AutoScaleMode.None; FormBorderStyle = FormBorderStyle.None;
            BackColor = Theme.White; ForeColor = Theme.Ink; Font = uiFont;
            DoubleBuffered = true; SetStyle(ControlStyles.ResizeRedraw, true);
            Icon = appIcon;
            Text = "RHINE LAB / 事务档案"; StartPosition = FormStartPosition.CenterScreen; KeyPreview = true;
            ClientSize = new Size(S(900), S(720)); MinimumSize = new Size(S(790), S(650));
            MaximumSize = Screen.PrimaryScreen.WorkingArea.Size;
            Controls.AddRange(new Control[] { list, title, due, requirements, close, add, save, complete, delete, less, more, startup });
            foreach (Control control in Controls) control.Font = Font;
            title.Input.MaxLength = 200; title.Input.AccessibleName = "事项名称";
            due.Input.MaxLength = 16; due.Input.AccessibleName = "截止时间，格式 年-月-日 时:分";
            requirements.Input.Failed += delegate(string text) { SetMessage(text, true); };
            close.Click += delegate { Close(); }; add.Click += delegate { NewItem(); };
            save.Click += SaveItem; complete.Click += ToggleDone; delete.Click += DeleteItem;
            less.Click += delegate { ChangeCount(-1); }; more.Click += delegate { ChangeCount(1); };
            countSave.Tick += delegate { FlushCount(); };
            list.SelectionChanged += delegate { LoadSelected(); };
            using (var key = Registry.CurrentUser.OpenSubKey(RunKey)) startup.Checked = key != null && key.GetValue("DesktopDDL") != null;
            startup.CheckedChanged += StartupChanged;
            ready = true; RefreshList(); NewItem(); UpdateCountButtons(); PerformLayout();
        }
        int S(int value) { return (int)Math.Round(value * scale); }
        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            int rounded = 2; Native.DwmSetWindowAttribute(Handle, 33, ref rounded, sizeof(int));
            int border = 0x00c9d2c0; Native.DwmSetWindowAttribute(Handle, 34, ref border, sizeof(int));
        }
        protected override void OnLayout(LayoutEventArgs e)
        {
            base.OnLayout(e); if (!ready) return;
            int x = ClientSize.Width - S(332), w = S(304), leftWidth = x - S(54);
            close.SetBounds(ClientSize.Width - S(65), S(22), S(38), S(34));
            add.SetBounds(x - S(154), S(127), S(130), S(32));
            list.SetBounds(S(28), S(173), leftWidth, ClientSize.Height - S(306));
            title.SetBounds(x, S(190), w, S(38)); due.SetBounds(x, S(258), w, S(38));
            requirements.SetBounds(x, S(332), w, ClientSize.Height - S(558));
            save.SetBounds(x, ClientSize.Height - S(214), w, S(38));
            complete.SetBounds(x, ClientSize.Height - S(166), w - S(94), S(34));
            delete.SetBounds(x + w - S(84), ClientSize.Height - S(166), S(84), S(34));
            int fy = ClientSize.Height - S(84);
            less.SetBounds(S(136), fy, S(34), S(32)); more.SetBounds(S(228), fy, S(34), S(32));
            startup.SetBounds(S(332), fy, S(270), S(32));
        }
        protected override void OnPaintBackground(PaintEventArgs e) { }
        protected override void OnPaint(PaintEventArgs e)
        {
            if (resourcesDisposed || ClientSize.Width <= 0 || ClientSize.Height <= 0) return;
            PaintContents(e.Graphics);
            base.OnPaint(e);
        }
        void PaintContents(Graphics g)
        {
            g.Clear(BackColor);
            int x = ClientSize.Width - S(332), w = S(304), footer = ClientSize.Height - S(106);
            using (var b = new SolidBrush(Theme.Green)) g.FillRectangle(b, S(28), S(28), S(4), S(14));
            Theme.Text(g, "事务档案", heading, new Rectangle(S(24), S(53), S(320), S(48)), Theme.Ink);
            Theme.Text(g, "待办 / " + pendingCount.ToString("00"), code, new Rectangle(S(27), S(135), S(150), S(24)), Theme.Green);
            Theme.Text(g, selectedId == null ? "NEW ENTRY / 新建" : "EDIT ENTRY / 编辑", code, new Rectangle(x, S(136), w, S(24)), Theme.Green);
            Theme.Text(g, "事项名称", small, new Rectangle(x, S(166), w, S(21)), Theme.Muted);
            Theme.Text(g, "截止时间   /   YYYY-MM-DD HH:MM", small, new Rectangle(x, S(232), w, S(23)), Theme.Muted);
            Theme.Text(g, "事项说明（可选）", small, new Rectangle(x, S(304), w, S(21)), Theme.Muted);
            Theme.Text(g, message, small, new Rectangle(x, ClientSize.Height - S(130), w, S(21)), error ? Theme.Red : Theme.Green);
            using (var pen = new Pen(Theme.Line))
            {
                g.DrawLine(pen, x - S(14), S(142), x - S(14), footer - S(17));
                g.DrawLine(pen, S(28), footer, ClientSize.Width - S(28), footer);
            }
            Theme.Text(g, "悬停展开数量", small, new Rectangle(S(28), footer + S(22), S(108), S(32)), Theme.Ink);
            Theme.Text(g, Store.Data.VisibleCount.ToString("00"), number, new Rectangle(S(173), footer + S(22), S(52), S(32)), Theme.Ink, true);
        }
        protected override void OnMouseDown(MouseEventArgs e)
        {
            base.OnMouseDown(e);
            if (e.Button == MouseButtons.Left && e.Y < S(126))
            { Native.ReleaseCapture(); Native.SendMessage(Handle, 0xA1, new IntPtr(2), IntPtr.Zero); }
        }
        protected override void WndProc(ref Message m)
        {
            base.WndProc(ref m);
            if (m.Msg == 0x84 && ready && m.Result == new IntPtr(1))
            {
                long value = m.LParam.ToInt64(); Point p = PointToClient(new Point((short)(value & 0xffff), (short)((value >> 16) & 0xffff)));
                if (p.X >= Width - S(10) && p.Y >= Height - S(10)) m.Result = new IntPtr(17);
            }
        }
        protected override void OnKeyDown(KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Escape) { Close(); e.Handled = true; }
            if (e.Control && e.KeyCode == Keys.S) { SaveItem(this, EventArgs.Empty); e.SuppressKeyPress = true; }
            if (e.Control && e.KeyCode == Keys.N) { NewItem(); e.SuppressKeyPress = true; }
            base.OnKeyDown(e);
        }
        void SetMessage(string text, bool isError)
        {
            message = text; error = isError; Invalidate(new Rectangle(ClientSize.Width - S(332), ClientSize.Height - S(130), S(306), S(23)));
        }
        void RefreshList()
        {
            pendingCount = Store.Data.Items.Count(z => !z.Done);
            list.UpdateItems(Store.Data.Items.OrderBy(z => z.Done).ThenBy(z => z.Due).ToList()); Invalidate();
        }
        public void SelectItem(string id) { list.SelectId(id); }
        void LoadSelected()
        {
            selectedId = list.SelectedId;
            var item = Store.Data.Items.FirstOrDefault(z => z.Id == selectedId); if (item == null) return;
            title.Input.Text = item.Title; due.Input.Text = item.Due.ToString("yyyy-MM-dd HH:mm");
            save.Text = "保存修改"; complete.Text = item.Done ? "恢复待办" : "标记完成";
            complete.Enabled = delete.Enabled = true; SetMessage("", false);
            requirements.Input.LoadContent(item.Requirements, item.RequirementsRtf); Invalidate();
        }
        void NewItem()
        {
            selectedId = null; list.SelectId(null); title.Input.Clear(); requirements.Input.LoadContent("", "");
            due.Input.Text = DateTime.Now.AddHours(1).ToString("yyyy-MM-dd HH:mm");
            save.Text = "添加事项"; complete.Text = "标记完成"; complete.Enabled = delete.Enabled = false;
            SetMessage("", false); title.Input.Focus(); Invalidate();
        }
        void SaveItem(object sender, EventArgs e)
        {
            if (string.IsNullOrWhiteSpace(title.Input.Text)) { SetMessage("请先写下事项名称。", true); title.Input.Focus(); return; }
            DateTime value;
            if (!DateTime.TryParseExact(due.Input.Text.Trim(), "yyyy-MM-dd HH:mm", CultureInfo.InvariantCulture, DateTimeStyles.None, out value))
            { SetMessage("日期格式：2026-10-08 18:30", true); due.Input.Focus(); return; }
            var item = Store.Data.Items.FirstOrDefault(z => z.Id == selectedId);
            if (item == null) { item = new Item(); Store.Data.Items.Add(item); }
            item.Title = title.Input.Text.Trim(); item.Due = DateTime.SpecifyKind(value, DateTimeKind.Local);
            item.Requirements = requirements.Input.Text.Trim();
            item.RequirementsRtf = requirements.Input.SavedRtf();
            if (Store.Save()) { RefreshList(); SelectItem(item.Id); SetMessage("已保存到本机。", false); }
        }
        void ToggleDone(object sender, EventArgs e)
        {
            var item = Store.Data.Items.FirstOrDefault(z => z.Id == selectedId); if (item == null) return;
            item.Done = !item.Done; if (Store.Save()) { RefreshList(); SelectItem(item.Id); SetMessage(item.Done ? "事项已完成。" : "已恢复到待办列表。", false); }
        }
        void DeleteItem(object sender, EventArgs e)
        {
            var item = Store.Data.Items.FirstOrDefault(z => z.Id == selectedId); if (item == null) return;
            if (MessageBox.Show(this, "删除“" + item.Title + "”？", "确认删除", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
            Store.Data.Items.Remove(item); if (Store.Save()) { RefreshList(); NewItem(); SetMessage("事项已删除。", false); }
        }
        void ChangeCount(int delta)
        {
            int next = Math.Max(1, Math.Min(20, Store.Data.VisibleCount + delta)); if (next == Store.Data.VisibleCount) return;
            Store.Data.VisibleCount = next; countDirty = true; UpdateCountButtons();
            Invalidate(new Rectangle(S(170), ClientSize.Height - S(84), S(56), S(34)));
            // Coalesce fast clicks into one disk write; notify the bar after saving.
            countSave.Stop(); countSave.Start();
        }
        void UpdateCountButtons() { less.Enabled = Store.Data.VisibleCount > 1; more.Enabled = Store.Data.VisibleCount < 20; }
        void FlushCount()
        {
            countSave.Stop(); if (countDirty && Store.Save()) countDirty = false;
        }
        void StartupChanged(object sender, EventArgs e)
        {
            try
            {
                using (var key = Registry.CurrentUser.CreateSubKey(RunKey))
                {
                    if (startup.Checked) key.SetValue("DesktopDDL", "\"" + Application.ExecutablePath + "\"");
                    else key.DeleteValue("DesktopDDL", false);
                }
                SetMessage(startup.Checked ? "已启用登录时启动。" : "已关闭登录时启动。", false);
            }
            catch (Exception ex)
            {
                SetMessage("无法修改启动设置：" + ex.Message, true);
                startup.CheckedChanged -= StartupChanged; startup.Checked = !startup.Checked; startup.CheckedChanged += StartupChanged;
            }
        }
        protected override void OnFormClosing(FormClosingEventArgs e) { FlushCount(); base.OnFormClosing(e); }
        protected override void Dispose(bool disposing)
        {
            if (!disposing || resourcesDisposed) { base.Dispose(disposing); return; }
            resourcesDisposed = true;
            countSave.Stop(); countSave.Dispose();
            try { base.Dispose(disposing); }
            finally
            {
                heading.Dispose(); small.Dispose(); code.Dispose(); number.Dispose(); uiFont.Dispose(); appIcon.Dispose();
            }
        }
    }
}
