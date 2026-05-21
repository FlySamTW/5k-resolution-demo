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

$shell = New-Object -ComObject Shell.Application
$shell.MinimizeAll()
Start-Sleep -Milliseconds 650

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
    Start-Sleep -Milliseconds 120
    $shell.UndoMinimizeAll()
}
