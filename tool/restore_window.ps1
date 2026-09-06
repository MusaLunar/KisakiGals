param([string]$Title = 'KisakiGals')
Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices;
public class RT {
  public delegate bool CB(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(CB c, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  public static IntPtr found = IntPtr.Zero;
  public static void Restore(int pid, string title) {
    EnumWindows((h, l) => {
      uint p; GetWindowThreadProcessId(h, out p);
      if (p == (uint)pid) {
        StringBuilder sb = new StringBuilder(128);
        GetWindowTextW(h, sb, 128);
        if (sb.ToString() == title) { found = h; return false; }
      }
      return true;
    }, IntPtr.Zero);
    if (found != IntPtr.Zero) {
      ShowWindow(found, 8);
      SetForegroundWindow(found);
      Console.WriteLine("restored " + found);
    } else {
      Console.WriteLine("not found");
    }
  }
}
"@
[RT]::Restore([int](Get-Process kisakigals).Id, $Title)
