$ErrorActionPreference = 'Stop'
Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class CloseReminder {
  public delegate bool Callback(IntPtr h, IntPtr p);
  [DllImport("user32.dll")] static extern bool EnumWindows(Callback c, IntPtr p);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  public static void Close(uint id) {
    EnumWindows(delegate(IntPtr h, IntPtr p) {
      uint pid; GetWindowThreadProcessId(h, out pid);
      var text = new StringBuilder(256); GetWindowText(h, text, text.Capacity);
      if (pid == id && text.ToString() == "DDL \u63d0\u9192\u680f") PostMessage(h, 0x10, IntPtr.Zero, IntPtr.Zero);
      return true;
    }, IntPtr.Zero);
  }
}
'@
Get-Process DesktopDDL -ErrorAction SilentlyContinue | ForEach-Object {
    [CloseReminder]::Close($_.Id)
    if (!$_.WaitForExit(5000)) { throw 'Please close the reminder from its tray menu, then retry.' }
}
