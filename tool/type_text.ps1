param([string]$Text = '', [int]$X = 528, [int]$Y = 486)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices;
public struct INP { public uint type; public uint pad; public ushort vk; public ushort sc; public uint fl; public uint t; public IntPtr ex; public IntPtr ex2; }
public class WI {
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindowW(string c, string t);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumCB c, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern uint SendInput(uint n, INP[] inputs, int size);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref PT p);
  public struct PT { public int X; public int Y; }
  public delegate bool EnumCB(IntPtr h, IntPtr l);

  public static INP Key(ushort vk, ushort sc, uint flags) {
    var i = new INP(); i.type = 1; i.vk = vk; i.sc = sc; i.fl = flags; return i;
  }
  public static void Chord(ushort vkMod, ushort scMod, ushort vkKey, ushort scKey) {
    var b = new INP[4];
    b[0] = Key(vkMod, scMod, 0); b[1] = Key(vkKey, scKey, 0);
    b[2] = Key(vkKey, scKey, 2); b[3] = Key(vkMod, scMod, 2);
    SendInput(4, b, System.Runtime.InteropServices.Marshal.SizeOf(typeof(INP)));
  }
}
"@

function Find-Window {
  $h = [WI]::FindWindowW($null, 'KisakiGals')
  if ($h -ne [IntPtr]::Zero) { return $h }
  $script:found = [IntPtr]::Zero
  $cb = [WI+EnumCB]{ param($hh, $l)
    if ([WI]::IsWindowVisible($hh)) {
      $sb = New-Object System.Text.StringBuilder 256
      [void][WI]::GetWindowTextW($hh, $sb, 256)
      if ($sb.ToString() -eq 'KisakiGals') { $script:found = $hh; return $false }
    }
    return $true
  }
  [void][WI]::EnumWindows($cb, [IntPtr]::Zero)
  return $script:found
}

$h = Find-Window
if ($h -eq [IntPtr]::Zero) { throw 'window not found' }
[void][WI]::SetForegroundWindow($h)
Start-Sleep -Milliseconds 300
[void][WI]::SetForegroundWindow($h)
Start-Sleep -Milliseconds 300

# click the field
$p = New-Object WI+PT
$p.X = $X; $p.Y = $Y
[void][WI]::ClientToScreen($h, [ref]$p)
[void][WI]::SetCursorPos($p.X, $p.Y)
Start-Sleep -Milliseconds 120
[void][WI]::mouse_event(2,0,0,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 60; [void][WI]::mouse_event(4,0,0,0,[UIntPtr]::Zero)
Start-Sleep -Milliseconds 250

# select all（粘贴会整体替换选区）
[WI]::Chord(0x11, 0x1D, 0x41, 0x1E)  # ctrl+a
Start-Sleep -Milliseconds 120

# clipboard paste via SendInput scancodes (ctrl+v)
if ($Text -ne '') {
  [System.Windows.Forms.Clipboard]::SetText($Text)
  Start-Sleep -Milliseconds 150
  [WI]::Chord(0x11, 0x1D, 0x56, 0x2F)  # ctrl+v
}
Write-Output "typed '$Text'"
