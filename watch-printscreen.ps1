param(
    [int]$IntervalMs = 700
)

$ErrorActionPreference = "SilentlyContinue"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$imagesDir = Join-Path $root "images"
if (-not (Test-Path $imagesDir)) {
    New-Item -Path $imagesDir -ItemType Directory | Out-Null
}

$createdNew = $false
$mutex = New-Object System.Threading.Mutex($true, "Global\5KResolutionDemoPrintScreenWatcher", [ref]$createdNew)
if (-not $createdNew) {
    Write-Host "PrintScreen watcher is already running."
    exit 0
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$lastHash = ""

function Get-PngBytesFromImage($image) {
    $stream = New-Object System.IO.MemoryStream
    try {
        $image.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
        return $stream.ToArray()
    }
    finally {
        $stream.Dispose()
    }
}

function Get-BytesHash([byte[]]$bytes) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return [Convert]::ToHexString($sha.ComputeHash($bytes))
    }
    finally {
        $sha.Dispose()
    }
}

Write-Host "PrintScreen watcher is running. Press Ctrl+C to stop." -ForegroundColor Green

while ($true) {
    try {
        if ([System.Windows.Forms.Clipboard]::ContainsImage()) {
            $image = [System.Windows.Forms.Clipboard]::GetImage()
            if ($null -ne $image) {
                $bytes = Get-PngBytesFromImage $image
                $hash = Get-BytesHash $bytes

                if ($hash -ne $lastHash) {
                    $lastHash = $hash
                    $stamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"
                    $target = Join-Path $imagesDir "printscreen-$stamp.png"
                    [System.IO.File]::WriteAllBytes($target, $bytes)
                    Write-Host "Added screenshot: $(Split-Path $target -Leaf)" -ForegroundColor Cyan
                }

                $image.Dispose()
            }
        }
    }
    catch {
        Start-Sleep -Milliseconds 250
    }

    Start-Sleep -Milliseconds $IntervalMs
}
