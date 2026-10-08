# Original geometric artwork; no fonts or third-party image assets.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
public static class DdlIconArt
{
    static readonly Color Olive = Color.FromArgb(77, 88, 65);
    static readonly Color Paper = Color.FromArgb(245, 242, 230);
    static readonly Color Gold = Color.FromArgb(209, 191, 145);
    static Bitmap Draw(int size, bool tray)
    {
        const int oversample = 4;
        using (var large = new Bitmap(size * oversample, size * oversample, PixelFormat.Format32bppArgb))
        {
            using (var g = Graphics.FromImage(large))
            {
                g.Clear(Color.Transparent);
                g.SmoothingMode = SmoothingMode.AntiAlias;
                g.ScaleTransform(size * oversample / 256f, size * oversample / 256f);
                var tile = new PointF[] {
                    new PointF(32, 12), new PointF(194, 12), new PointF(244, 62),
                    new PointF(244, 224), new PointF(224, 244), new PointF(32, 244),
                    new PointF(12, 224), new PointF(12, 32)
                };
                using (var fill = new SolidBrush(Olive)) g.FillPolygon(fill, tile);
                if (!tray && size >= 32)
                {
                    using (var line = new Pen(Gold, 5))
                    {
                        g.DrawLines(line, new PointF[] { new PointF(194, 23), new PointF(194, 62), new PointF(233, 62) });
                        g.DrawLine(line, 39, 39, 90, 39);
                        g.DrawLine(line, 39, 51, 68, 51);
                        g.DrawLine(line, 168, 217, 215, 217);
                    }
                }
                float radius = tray ? 76 : 68;
                float cy = tray ? 128 : 135;
                using (var ring = new Pen(Paper, tray ? 17 : 13))
                    g.DrawEllipse(ring, 128 - radius, cy - radius, radius * 2, radius * 2);
                using (var hand = new Pen(Paper, tray ? 19 : 16))
                {
                    hand.StartCap = hand.EndCap = LineCap.Round;
                    hand.LineJoin = LineJoin.Round;
                    g.DrawLines(hand, new PointF[] { new PointF(128, cy - 42), new PointF(128, cy), new PointF(164, cy + 22) });
                }
            }
            var result = new Bitmap(size, size, PixelFormat.Format32bppArgb);
            using (var g = Graphics.FromImage(result))
            {
                g.CompositingMode = CompositingMode.SourceCopy;
                g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                g.DrawImage(large, new Rectangle(0, 0, size, size), 0, 0, large.Width, large.Height, GraphicsUnit.Pixel);
            }
            return result;
        }
    }
    // Uncompressed 32-bit ICO frames with explicit transparency masks are also
    // readable by .NET Framework Icon, Explorer, and the WinForms notification area.
    static byte[] Frame(Bitmap image)
    {
        int size = image.Width, maskStride = ((size + 31) / 32) * 4;
        using (var stream = new MemoryStream())
        using (var writer = new BinaryWriter(stream))
        {
            writer.Write(40); writer.Write(size); writer.Write(size * 2);
            writer.Write((short)1); writer.Write((short)32);
            writer.Write(0); writer.Write(size * size * 4 + maskStride * size);
            writer.Write(0); writer.Write(0); writer.Write(0); writer.Write(0);
            for (int y = size - 1; y >= 0; y--)
                for (int x = 0; x < size; x++)
                {
                    Color pixel = image.GetPixel(x, y);
                    writer.Write(pixel.B); writer.Write(pixel.G); writer.Write(pixel.R); writer.Write(pixel.A);
                }
            for (int y = size - 1; y >= 0; y--)
            {
                var mask = new byte[maskStride];
                for (int x = 0; x < size; x++)
                    if (image.GetPixel(x, y).A == 0) mask[x / 8] |= (byte)(128 >> (x % 8));
                writer.Write(mask);
            }
            return stream.ToArray();
        }
    }
    public static void Generate(string folder)
    {
        Directory.CreateDirectory(folder);
        int[] sizes = { 16, 20, 24, 32, 40, 48, 64, 128, 256 };
        foreach (bool tray in new bool[] { false, true })
        {
            string name = tray ? "DesktopDDL-tray" : "DesktopDDL";
            var frames = new byte[sizes.Length][];
            for (int i = 0; i < sizes.Length; i++)
                using (var bitmap = Draw(sizes[i], tray)) frames[i] = Frame(bitmap);
            using (var writer = new BinaryWriter(File.Create(Path.Combine(folder, name + ".ico"))))
            {
                writer.Write((short)0); writer.Write((short)1); writer.Write((short)sizes.Length);
                int offset = 6 + sizes.Length * 16;
                for (int i = 0; i < sizes.Length; i++)
                {
                    writer.Write((byte)(sizes[i] == 256 ? 0 : sizes[i]));
                    writer.Write((byte)(sizes[i] == 256 ? 0 : sizes[i]));
                    writer.Write((byte)0); writer.Write((byte)0);
                    writer.Write((short)1); writer.Write((short)32);
                    writer.Write(frames[i].Length); writer.Write(offset);
                    offset += frames[i].Length;
                }
                foreach (byte[] frame in frames) writer.Write(frame);
            }
            using (var bitmap = Draw(256, tray)) bitmap.Save(Path.Combine(folder, name + ".png"), ImageFormat.Png);
        }
        using (var preview = new Bitmap(640, 300))
        using (var g = Graphics.FromImage(preview))
        {
            g.Clear(Paper);
            using (var brush = new SolidBrush(Color.FromArgb(31, 34, 32))) g.FillRectangle(brush, 320, 0, 320, 300);
            foreach (int x in new int[] { 0, 320 })
            {
                using (var app = Draw(160, false)) g.DrawImageUnscaled(app, x + 80, 16);
                int left = x + 44;
                foreach (int size in new int[] { 16, 20, 24, 32, 48 })
                {
                    using (var icon = Draw(size, true)) g.DrawImageUnscaled(icon, left, 224 - size / 2);
                    left += size + 16;
                }
            }
            preview.Save(Path.Combine(folder, "icon-preview.png"), ImageFormat.Png);
        }
    }
}
'@
[DdlIconArt]::Generate($PSScriptRoot)
Write-Host "Generated multi-resolution icons and preview in $PSScriptRoot"
