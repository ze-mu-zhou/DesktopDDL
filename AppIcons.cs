using System;
using System.Drawing;
using System.Windows.Forms;

namespace DesktopDDL
{
    internal static class AppIcons
    {
        // Each caller owns its clone. No loose files or dependency on the current directory.
        static Icon Load(string name, Size size)
        {
            using (var stream = typeof(AppIcons).Assembly.GetManifestResourceStream(name))
            {
                if (stream == null) throw new InvalidOperationException("Missing embedded icon: " + name);
                using (var icon = new Icon(stream, size)) return (Icon)icon.Clone();
            }
        }
        internal static Icon ApplicationIcon() { return Load("DesktopDDL.App.ico", SystemInformation.IconSize); }
        internal static Icon TrayIcon() { return Load("DesktopDDL.Tray.ico", SystemInformation.SmallIconSize); }
    }
}
