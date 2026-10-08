using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.Windows.Forms;
using Microsoft.Win32;

namespace DesktopDDL
{
    public sealed class ReminderBar : PixelWindow
    {
        readonly PixelWindow panel = new PixelWindow();
        readonly Timer animation = new Timer { Interval = 16 };
        readonly Timer leave = new Timer { Interval = 420 };
        readonly Timer expand = new Timer { Interval = 230 };
        readonly Timer clock = new Timer();
        readonly Stopwatch motion = new Stopwatch();
        readonly NotifyIcon tray = new NotifyIcon();
        readonly Icon appIcon = AppIcons.ApplicationIcon();
        readonly Icon trayIcon = AppIcons.TrayIcon();
        readonly ContextMenuStrip menu = new ContextMenuStrip();
        readonly Font titleFont = new Font("Microsoft YaHei UI", 10, FontStyle.Bold);
        readonly Font detailFont = new Font("Microsoft YaHei UI", 8.5f);
        readonly float scale;
        readonly int cardWidth, rowHeight, gap;
        Rectangle work;
        List<Item> items;
        int stage, rows, shownWidth, shownHeight, fromWidth, fromHeight, targetWidth, targetHeight;
        bool disposed;
        Manager manager;
        sealed class CardText
        {
            internal string Title, Detail;
            internal bool Overdue;
        }
        CardText[] renderedCards;
        // Read-only diagnostics used by regression tests, not background sampling.
        public int Stage { get { return stage; } }
        public Rectangle PanelBounds { get { return panel.Bounds; } }
        public bool PanelVisible { get { return panel.Visible; } }
        public bool Idle { get { return !animation.Enabled && !leave.Enabled && !expand.Enabled && !clock.Enabled; } }
        public int PanelPresentCount { get { return panel.PresentCount; } }
        public bool PanelHasSurface { get { return panel.HasSurface; } }
        public int CacheBuilds { get; private set; }
        public long PanelCacheBytes { get { return panel.PixelBytes; } }
        public ReminderBar()
        {
            using (var g = Graphics.FromHwnd(IntPtr.Zero)) scale = g.DpiX / 96f;
            cardWidth = S(370); rowHeight = S(62); gap = S(5);
            Text = "DDL 提醒栏"; panel.Text = "DDL 事项栏";
            Icon = panel.Icon = appIcon;
            items = Store.Pending();
            BuildArrow(); PlaceArrow();
            menu.BackColor = Theme.Paper; menu.ForeColor = Theme.Ink; menu.ShowImageMargin = false;
            menu.Items.Add("管理事项 / 设置", null, delegate { OpenManager(); });
            menu.Items.Add("打开数据文件夹", null, delegate { System.IO.Directory.CreateDirectory(Store.Folder); Process.Start(Store.Folder); });
            menu.Items.Add(new ToolStripSeparator()); menu.Items.Add("退出提醒栏", null, delegate { Close(); });
            ContextMenuStrip = panel.ContextMenuStrip = menu;
            menu.Closed += delegate { ArmLeave(); };
            tray.Icon = trayIcon; tray.Text = "DDL 提醒栏 · 莱茵生命DDL部";
            tray.ContextMenuStrip = menu; tray.Visible = true; tray.DoubleClick += delegate { OpenManager(); };
            MouseEnter += delegate { leave.Stop(); if (stage == 0) SetStage(1); };
            MouseLeave += delegate { ArmLeave(); };
            MouseDoubleClick += delegate(object s, MouseEventArgs e) { if (e.Button == MouseButtons.Left) OpenManager(); };
            panel.MouseEnter += delegate
            {
                leave.Stop();
                if (stage == 1 && panel.PointToClient(Cursor.Position).Y < rowHeight && !expand.Enabled) expand.Start();
            };
            panel.MouseMove += delegate(object s, MouseEventArgs e)
            {
                leave.Stop();
                if (stage == 1 && e.Y < rowHeight && !expand.Enabled) expand.Start();
                else if (e.Y >= rowHeight) expand.Stop();
            };
            panel.MouseLeave += delegate { expand.Stop(); ArmLeave(); };
            panel.MouseClick += delegate(object s, MouseEventArgs e)
            {
                if (e.Button != MouseButtons.Left) return;
                int index = e.Y / (rowHeight + gap);
                OpenManager(index < items.Count ? items[index].Id : null);
            };
            expand.Tick += delegate
            {
                expand.Stop(); Point p = panel.PointToClient(Cursor.Position);
                if (stage == 1 && panel.Visible && new Rectangle(0, 0, panel.Width, rowHeight).Contains(p)) SetStage(2);
            };
            leave.Tick += delegate
            {
                leave.Stop(); if (!menu.Visible && !PointerInside()) SetStage(0);
            };
            animation.Tick += Animate;
            clock.Tick += delegate { clock.Stop(); if (stage > 0) { if (BuildCards()) PresentPanel(); ScheduleClock(); } };
            Store.Changed += DataChanged;
            SystemEvents.DisplaySettingsChanged += DisplayChanged;
            SystemEvents.UserPreferenceChanged += PreferencesChanged;
        }
        int S(int value) { return (int)Math.Round(value * scale); }
        void BuildArrow()
        {
            using (var image = new Bitmap(S(30), S(32), PixelFormat.Format32bppPArgb))
            using (var g = Graphics.FromImage(image))
            {
                // Alpha 1 makes the tiny hover target solid for hit-testing without a visible box.
                g.Clear(Color.FromArgb(1, 255, 255, 255)); g.SmoothingMode = SmoothingMode.AntiAlias;
                using (var pen = new Pen(Color.White, S(4)))
                {
                    pen.StartCap = pen.EndCap = LineCap.Round; pen.LineJoin = LineJoin.Round;
                    float cx = image.Width / 2f, cy = image.Height / 2f;
                    g.DrawLines(pen, new PointF[] { new PointF(cx + S(4), cy - S(7)), new PointF(cx - S(3), cy), new PointF(cx + S(4), cy + S(7)) });
                }
                SetPixels(image);
            }
        }
        void PlaceArrow()
        {
            work = Screen.PrimaryScreen.WorkingArea;
            Present(new Rectangle(work.Right - S(38), work.Top + S(44), S(30), S(32)));
        }
        bool PointerInside()
        {
            Point p = Cursor.Position;
            return Bounds.Contains(p) || (panel.Visible && panel.Bounds.Contains(p));
        }
        void ArmLeave() { leave.Stop(); if (stage > 0) leave.Start(); }
        void SetStage(int next)
        {
            if (disposed || stage == next) return;
            stage = next; expand.Stop();
            if (next > 0)
            {
                BuildCards();
                ScheduleClock();
            }
            else { clock.Stop(); leave.Stop(); }
            StartMotion();
        }
        void StartMotion()
        {
            fromWidth = shownWidth; fromHeight = shownHeight == 0 ? rowHeight : shownHeight;
            targetWidth = stage == 0 ? 0 : cardWidth;
            targetHeight = stage == 2 ? rows * (rowHeight + gap) - gap : rowHeight;
            motion.Restart(); animation.Start(); Animate(null, EventArgs.Empty);
        }
        void Animate(object sender, EventArgs e)
        {
            double t = Math.Min(1, motion.Elapsed.TotalMilliseconds / 190.0);
            double eased = 1 - Math.Pow(1 - t, 3);
            int w = (int)Math.Round(fromWidth + (targetWidth - fromWidth) * eased);
            int h = (int)Math.Round(fromHeight + (targetHeight - fromHeight) * eased);
            if (w != shownWidth || h != shownHeight)
            {
                shownWidth = w; shownHeight = h; PresentPanel();
            }
            if (t < 1) return;
            animation.Stop(); motion.Stop();
            if (stage == 0)
            {
                panel.Hide(); panel.ReleasePixels(); renderedCards = null; shownWidth = 0; shownHeight = rowHeight;
                // Absolutely no timers are left running when collapsed.
                leave.Stop(); expand.Stop(); clock.Stop();
            }
        }
        void PresentPanel()
        {
            if (shownWidth <= 0) { panel.Hide(); return; }
            panel.Present(new Rectangle(Left - shownWidth, work.Top + S(16), shownWidth, shownHeight));
            if (!panel.Visible) panel.Show(this);
        }
        int NextRefreshDelay(DateTime now)
        {
            if (stage == 0 || items.Count == 0) return 0;
            double delay = 60000 - now.Second * 1000 - now.Millisecond + 30;
            // Only deadlines that can actually be seen may wake the clock.
            for (int i = 0; i < Math.Min(rows, items.Count); i++)
            {
                double until = (items[i].Due - now).TotalMilliseconds + 30;
                if (until > 0 && until < delay) delay = until;
            }
            return Math.Max(100, (int)delay);
        }
        void ScheduleClock()
        {
            clock.Stop();
            int delay = NextRefreshDelay(DateTime.Now);
            if (delay == 0) return;
            clock.Interval = delay; clock.Start();
        }
        bool BuildCards() { return BuildCardsAt(DateTime.Now); }
        bool BuildCardsAt(DateTime now)
        {
            int fits = Math.Max(1, (work.Height - S(32)) / (rowHeight + gap));
            int nextRows = stage == 2 ? Math.Max(1, Math.Min(Math.Min(items.Count, Store.Data.VisibleCount), fits)) : 1;
            var nextCards = new CardText[nextRows];
            bool changed = !panel.HasSurface || renderedCards == null || renderedCards.Length != nextRows;
            for (int i = 0; i < nextRows; i++)
            {
                Item item = i < items.Count ? items[i] : null;
                var card = new CardText {
                    Title = item == null ? "暂无待办事项" : item.Title,
                    Detail = item == null ? "" : item.Due.ToString("yyyy.MM.dd  HH:mm") + "  /  " + Remaining(item.Due, now),
                    Overdue = item != null && item.Due <= now
                };
                nextCards[i] = card;
                if (!changed)
                {
                    var old = renderedCards[i];
                    changed = card.Title != old.Title || card.Detail != old.Detail || card.Overdue != old.Overdue;
                }
            }
            if (!changed) return false;
            rows = nextRows;
            int height = rows * (rowHeight + gap) - gap;
            using (var image = new Bitmap(cardWidth, height, PixelFormat.Format32bppPArgb))
            {
                image.SetResolution(96 * scale, 96 * scale);
                using (var g = Graphics.FromImage(image))
                {
                    g.Clear(Color.Transparent); g.SmoothingMode = SmoothingMode.AntiAlias;
                    g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
                    for (int i = 0; i < rows; i++)
                    {
                        int y = i * (rowHeight + gap);
                        var rect = new Rectangle(0, y, cardWidth - S(3), rowHeight - 1);
                        using (var path = Theme.CutCard(rect, S(9)))
                        using (var fill = new LinearGradientBrush(rect, Theme.White, Theme.Paper, 90f))
                        using (var pen = new Pen(Theme.Line)) { g.FillPath(fill, path); g.DrawPath(pen, path); }
                        CardText card = nextCards[i];
                        Color accent = card.Overdue ? Theme.Red : Theme.Green;
                        using (var brush = new SolidBrush(accent)) g.FillRectangle(brush, 0, y, S(3), rowHeight - 1);
                        Draw(g, card.Title, titleFont, Theme.Ink, new Rectangle(S(15), y + S(10), cardWidth - S(48), S(25)));
                        if (card.Detail.Length > 0)
                            Draw(g, card.Detail, detailFont, accent, new Rectangle(S(15), y + S(37), cardWidth - S(30), S(22)));
                        using (var pen = new Pen(Theme.Gold))
                        {
                            int x = cardWidth - S(22), py = y + S(21);
                            g.DrawLine(pen, x - S(3), py, x + S(3), py); g.DrawLine(pen, x, py - S(3), x, py + S(3));
                        }
                    }
                }
                panel.SetPixels(image);
            }
            renderedCards = nextCards; CacheBuilds++; return true;
        }
        static void Draw(Graphics g, string text, Font font, Color color, Rectangle box)
        {
            using (var b = new SolidBrush(color))
            using (var format = new StringFormat { FormatFlags = StringFormatFlags.NoWrap, Trimming = StringTrimming.EllipsisCharacter, LineAlignment = StringAlignment.Center })
                g.DrawString(text, font, b, box, format);
        }
        static string Remaining(DateTime due, DateTime now)
        {
            TimeSpan t = due - now; bool past = t.Ticks < 0; int minutes = Math.Max(1, (int)Math.Ceiling(t.Duration().TotalMinutes));
            string text = minutes >= 1440 ? (minutes / 1440) + "天 " + (minutes % 1440 / 60) + "小时" : minutes >= 60 ? (minutes / 60) + "小时 " + (minutes % 60) + "分" : minutes + "分钟";
            return (past ? "已逾期 " : "剩余 ") + text;
        }
        void DataChanged(object sender, EventArgs e)
        {
            items = Store.Pending();
            if (stage > 0)
            {
                int oldRows = rows;
                if (BuildCards()) PresentPanel();
                if (oldRows != rows) StartMotion();
                ScheduleClock();
            }
        }
        void PreferencesChanged(object sender, UserPreferenceChangedEventArgs e) { DisplayChanged(sender, EventArgs.Empty); }
        void DisplayChanged(object sender, EventArgs e)
        {
            if (disposed || !IsHandleCreated) return;
            BeginInvoke((Action)delegate
            {
                if (disposed) return;
                var next = Screen.PrimaryScreen.WorkingArea; if (next == work) return;
                SetStage(0); PlaceArrow();
            });
        }
        public void OpenManager(string id = null)
        {
            SetStage(0);
            if (manager == null || manager.IsDisposed)
            {
                manager = new Manager();
                manager.FormClosed += delegate { manager = null; };
                manager.Show();
            }
            if (manager.WindowState == FormWindowState.Minimized) manager.WindowState = FormWindowState.Normal;
            manager.Activate(); if (id != null) manager.SelectItem(id);
        }
        protected override void Dispose(bool disposing)
        {
            if (disposing && !disposed)
            {
                disposed = true;
                Store.Changed -= DataChanged; SystemEvents.DisplaySettingsChanged -= DisplayChanged; SystemEvents.UserPreferenceChanged -= PreferencesChanged;
                animation.Dispose(); leave.Dispose(); expand.Dispose(); clock.Dispose();
                tray.Visible = false; tray.Dispose(); panel.Dispose(); menu.Dispose();
                if (manager != null) { manager.Dispose(); manager = null; }
                renderedCards = null; items = null;
                titleFont.Dispose(); detailFont.Dispose();
                appIcon.Dispose(); trayIcon.Dispose();
            }
            base.Dispose(disposing);
        }
    }
}
