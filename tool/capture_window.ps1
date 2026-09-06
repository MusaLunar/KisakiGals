param([string]$out, [string]$keys = "")
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32Cap5 {
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
"@
$p = Get-Process kisakigals -ErrorAction Stop
$h = $p.MainWindowHandle
# ALT 解锁前台 + 激活
[Win32Cap5]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero)
[Win32Cap5]::SetForegroundWindow($h) | Out-Null
[Win32Cap5]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 500
if ($keys -ne "") {
  [System.Windows.Forms.SendKeys]::SendWait($keys)
  Start-Sleep -Milliseconds 600
}
# 置顶防止遮挡
$HWND_TOPMOST = New-Object IntPtr (-1); $HWND_NOTOPMOST = New-Object IntPtr (-2)
[Win32Cap5]::SetWindowPos($h, $HWND_TOPMOST, 0,0,0,0, 0x53) | Out-Null
Start-Sleep -Milliseconds 300
$r = New-Object Win32Cap5+RECT
[Win32Cap5]::GetWindowRect($h, [ref]$r) | Out-Null
$w = $r.R - $r.L; $ht = $r.B - $r.T
$bmp = New-Object System.Drawing.Bitmap($w, $ht)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($r.L, $r.T, 0, 0, $bmp.Size)
$g.Dispose()
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
[Win32Cap5]::SetWindowPos($h, $HWND_NOTOPMOST, 0,0,0,0, 0x53) | Out-Null
Write-Output "saved $out ($w x $ht)"
