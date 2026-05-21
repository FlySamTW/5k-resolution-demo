param(
    [string]$ImagesDir = ""
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $ImagesDir) {
    $ImagesDir = Join-Path $root "images"
}
if (-not (Test-Path $ImagesDir)) {
    New-Item -Path $ImagesDir -ItemType Directory | Out-Null
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Win32CaptureHelper {
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@

$foreground = [Win32CaptureHelper]::GetForegroundWindow()
if ($foreground -ne [IntPtr]::Zero) {
    [Win32CaptureHelper]::ShowWindow($foreground, 6) | Out-Null
    Start-Sleep -Milliseconds 450
}

$bounds = [System.Windows.Forms.SystemInformation]::VirtualScreen
$bitmap = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)

try {
    $graphics.CopyFromScreen($bounds.Left, $bounds.Top, 0, 0, $bounds.Size)
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"
    $name = "desktop-$stamp.png"
    $target = Join-Path $ImagesDir $name
    $bitmap.Save($target, [System.Drawing.Imaging.ImageFormat]::Png)
    Write-Output $name
}
finally {
    $graphics.Dispose()
    $bitmap.Dispose()
    if ($foreground -ne [IntPtr]::Zero) {
        Start-Sleep -Milliseconds 120
        [Win32CaptureHelper]::ShowWindow($foreground, 9) | Out-Null
    }
}
