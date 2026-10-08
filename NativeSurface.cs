using System;
using System.ComponentModel;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace DesktopDDL
{
    internal static class Native
    {
        [StructLayout(LayoutKind.Sequential)] internal struct POINT { public int X, Y; public POINT(int x, int y) { X = x; Y = y; } }
        [StructLayout(LayoutKind.Sequential)] internal struct SIZE { public int Width, Height; public SIZE(int w, int h) { Width = w; Height = h; } }
        [StructLayout(LayoutKind.Sequential, Pack = 1)] internal struct BLEND { public byte Operation, Flags, Alpha, Format; }
        [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
        [DllImport("user32.dll")] internal static extern IntPtr GetDC(IntPtr window);
        [DllImport("user32.dll")] internal static extern int ReleaseDC(IntPtr window, IntPtr dc);
        [DllImport("gdi32.dll")] internal static extern IntPtr CreateCompatibleDC(IntPtr dc);
        [DllImport("gdi32.dll")] internal static extern bool DeleteDC(IntPtr dc);
        [DllImport("gdi32.dll")] internal static extern IntPtr SelectObject(IntPtr dc, IntPtr obj);
        [DllImport("gdi32.dll")] internal static extern bool DeleteObject(IntPtr obj);
        [DllImport("user32.dll", SetLastError = true)] internal static extern bool UpdateLayeredWindow(IntPtr window, IntPtr screen, ref POINT dest, ref SIZE size, IntPtr source, ref POINT sourcePoint, int key, ref BLEND blend, int flags);
        [DllImport("user32.dll")] internal static extern bool ReleaseCapture();
        [DllImport("user32.dll")] internal static extern IntPtr SendMessage(IntPtr window, int message, IntPtr w, IntPtr l);
        [DllImport("dwmapi.dll")] internal static extern int DwmSetWindowAttribute(IntPtr window, int attribute, ref int value, int size);
    }
    // A cached 32-bit DIB: no bitmap allocation, text rendering or GDI object creation per frame.
    internal sealed class PixelSurface : IDisposable
    {
        internal IntPtr DC;
        IntPtr bitmap, previous;
        internal readonly Size Size;
        internal PixelSurface(Bitmap image)
        {
            Size = image.Size;
            DC = Native.CreateCompatibleDC(IntPtr.Zero);
            if (DC == IntPtr.Zero) throw new Win32Exception();
            try
            {
                bitmap = image.GetHbitmap(Color.FromArgb(0));
                previous = Native.SelectObject(DC, bitmap);
                if (previous == IntPtr.Zero || previous == new IntPtr(-1)) throw new Win32Exception();
            }
            catch { Dispose(); throw; }
        }
        public void Dispose()
        {
            if (DC != IntPtr.Zero && previous != IntPtr.Zero) Native.SelectObject(DC, previous);
            if (bitmap != IntPtr.Zero) Native.DeleteObject(bitmap);
            if (DC != IntPtr.Zero) Native.DeleteDC(DC);
            DC = bitmap = previous = IntPtr.Zero;
        }
    }
    public class PixelWindow : Form
    {
        PixelSurface surface;
        public int PresentCount { get; private set; }
        public bool HasSurface { get { return surface != null; } }
        public long PixelBytes { get { return surface == null ? 0 : (long)surface.Size.Width * surface.Size.Height * 4; } }
        public PixelWindow()
        {
            FormBorderStyle = FormBorderStyle.None; ShowInTaskbar = false; TopMost = true;
            StartPosition = FormStartPosition.Manual; AutoScaleMode = AutoScaleMode.None;
        }
        protected override bool ShowWithoutActivation { get { return true; } }
        protected override CreateParams CreateParams
        {
            get { var p = base.CreateParams; p.ExStyle |= 0x80000 | 0x08000000 | 0x80; return p; }
        }
        protected override void OnPaintBackground(PaintEventArgs e) { }
        protected override void OnPaint(PaintEventArgs e) { }
        public void SetPixels(Bitmap image)
        {
            var next = new PixelSurface(image); var old = surface; surface = next;
            if (old != null) old.Dispose();
        }
        public void ReleasePixels() { if (surface != null) { surface.Dispose(); surface = null; } }
        public void Present(Rectangle bounds)
        {
            if (surface == null || bounds.Width <= 0 || bounds.Height <= 0) return;
            var destination = new Native.POINT(bounds.X, bounds.Y);
            var size = new Native.SIZE(Math.Min(bounds.Width, surface.Size.Width), Math.Min(bounds.Height, surface.Size.Height));
            var source = new Native.POINT(0, 0);
            var blend = new Native.BLEND { Alpha = 255, Format = 1 };
            // Window position, size and pixels are committed together by DWM.
            if (!Native.UpdateLayeredWindow(Handle, IntPtr.Zero, ref destination, ref size, surface.DC, ref source, 0, ref blend, 2))
                throw new Win32Exception(Marshal.GetLastWin32Error());
            // ULW does not consistently send WM_WINDOWPOSCHANGED on all Windows builds.
            // Synchronize WinForms' cached geometry without another native SetWindowPos.
            UpdateBounds(bounds.X, bounds.Y, size.Width, size.Height, size.Width, size.Height);
            PresentCount++;
        }
        protected override void Dispose(bool disposing) { if (disposing) ReleasePixels(); base.Dispose(disposing); }
    }
}
