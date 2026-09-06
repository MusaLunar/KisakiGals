param(
  [Parameter(Position=0)][string]$Cmd,
  [Parameter(Position=1)][string]$A1,
  [Parameter(Position=2)][string]$A2
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class W {
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindowW(string cls, string title);
  [DllImport("user32.dll")] public static extern bool EnumWindows(CB c, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, System.Text.StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  public delegate bool CB(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte sc, uint f, UIntPtr e);
  [DllImport("Shcore.dll")] public static extern int SetProcessDpiAwareness(int v);
  public struct RECT { public int L; public int T; public int R; public int B; }
  public struct POINT { public int X; public int Y; }
}
"@
[void][W]::SetProcessDpiAwareness(2)

function Get-Hwnd {
  $h = [W]::FindWindowW($null, 'KisakiGals')
  if ($h -ne [IntPtr]::Zero) { return $h }
  # fallback: enumerate visible top-level windows by title
  $found = [IntPtr]::Zero
  $cb = [W+CB]{ param($hh, $l)
    if ([W]::IsWindowVisible($hh)) {
      $sb = New-Object System.Text.StringBuilder 256
      [void][W]::GetWindowTextW($hh, $sb, 256)
      if ($sb.ToString() -eq 'KisakiGals') { $script:found = $hh; return $false }
    }
    return $true
  }
  [void][W]::EnumWindows($cb, [IntPtr]::Zero)
  if ($script:found -eq [IntPtr]::Zero) { throw 'KisakiGals window not found' }
  return $script:found
}

function Activate-Window([IntPtr]$h) {
  # ALT trick to bypass foreground lock
  [void][W]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero)
  [void][W]::SetForegroundWindow($h)
  [void][W]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 350
}

switch ($Cmd) {
  'shot' {
    $h = Get-Hwnd
    Activate-Window $h
    $r = New-Object W+RECT
    [void][W]::GetClientRect($h, [ref]$r)
    $p = New-Object W+POINT
    $p.X = 0; $p.Y = 0
    [void][W]::ClientToScreen($h, [ref]$p)
    $w = $r.R - $r.L; $ht = $r.B - $r.T
    $bmp = New-Object System.Drawing.Bitmap($w, $ht)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($p.X, $p.Y, 0, 0, (New-Object System.Drawing.Size($w, $ht)))
    $g.Dispose()
    $bmp.Save($A1, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Output "shot $w x $ht at screen($($p.X),$($p.Y)) -> $A1"
  }
  'click' {
    $h = Get-Hwnd
    Activate-Window $h
    $p = New-Object W+POINT
    $p.X = [int]$A1; $p.Y = [int]$A2
    [void][W]::ClientToScreen($h, [ref]$p)
    [void][W]::SetCursorPos($p.X, $p.Y)
    Start-Sleep -Milliseconds 120
    [void][W]::mouse_event(0x02, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 60
    [void][W]::mouse_event(0x04, 0, 0, 0, [UIntPtr]::Zero)
    Write-Output "clicked client($A1,$A2) screen($($p.X),$($p.Y))"
  }
  'key' {
    $h = Get-Hwnd
    Activate-Window $h
    $vk = [byte]$A1
    [void][W]::keybd_event($vk, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 60
    [void][W]::keybd_event($vk, 0, 2, [UIntPtr]::Zero)
    Write-Output "key sent vk=$vk"
  }
  'rect' {
    $h = Get-Hwnd
    $r = New-Object W+RECT
    [void][W]::GetClientRect($h, [ref]$r)
    $p = New-Object W+POINT
    [void][W]::ClientToScreen($h, [ref]$p)
    Write-Output "client $($r.R - $r.L) x $($r.B - $r.T) origin($($p.X),$($p.Y))"
  }
  default { Write-Output 'usage: ui.ps1 shot|click|key|rect [args]' }
}
