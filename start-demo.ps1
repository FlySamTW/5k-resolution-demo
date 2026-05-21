param(
    [int]$Port = 8899
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$imagesDir = Join-Path $root "images"
if (-not (Test-Path $imagesDir)) {
    New-Item -Path $imagesDir -ItemType Directory | Out-Null
}

$watcherScript = Join-Path $root "watch-printscreen.ps1"
if (Test-Path $watcherScript) {
    Start-Process powershell -WindowStyle Hidden -ArgumentList @(
        "-STA",
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        "`"$watcherScript`""
    ) | Out-Null
}

$allowedMediaExt = @(".png", ".jpg", ".jpeg", ".webp", ".mp4", ".webm")

$listener = New-Object System.Net.HttpListener
$prefix = "http://localhost:$Port/"
$listener.Prefixes.Add($prefix)
$listener.Start()

Write-Host "Demo server is running: $prefix" -ForegroundColor Green
Write-Host "Press Ctrl+C to stop the server." -ForegroundColor Yellow

function Get-ContentType([string]$path) {
    switch ([IO.Path]::GetExtension($path).ToLowerInvariant()) {
        ".html" { "text/html; charset=utf-8" }
        ".js" { "application/javascript; charset=utf-8" }
        ".css" { "text/css; charset=utf-8" }
        ".json" { "application/json; charset=utf-8" }
        ".png" { "image/png" }
        ".jpg" { "image/jpeg" }
        ".jpeg" { "image/jpeg" }
        ".webp" { "image/webp" }
        ".mp4" { "video/mp4" }
        ".webm" { "video/webm" }
        default { "application/octet-stream" }
    }
}

function Write-JsonResponse($response, $obj) {
    $json = $obj | ConvertTo-Json -Depth 5 -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    $response.StatusCode = 200
    $response.ContentType = "application/json; charset=utf-8"
    $response.ContentLength64 = $bytes.Length
    $response.OutputStream.Write($bytes, 0, $bytes.Length)
}

function Write-FileResponse($request, $response, [string]$path) {
    if (-not (Test-Path $path -PathType Leaf)) {
        $response.StatusCode = 404
        return
    }

    $file = Get-Item -LiteralPath $path
    $length = [int64]$file.Length
    $start = [int64]0
    $end = [int64]($length - 1)
    $range = $request.Headers["Range"]

    if ($range -match "^bytes=(\d*)-(\d*)$") {
        if ($matches[1]) { $start = [int64]$matches[1] }
        if ($matches[2]) { $end = [int64]$matches[2] }
        if ($start -le $end -and $end -lt $length) {
            $response.StatusCode = 206
            $response.AddHeader("Accept-Ranges", "bytes")
            $response.AddHeader("Content-Range", "bytes $start-$end/$length")
        }
        else {
            $response.StatusCode = 416
            $response.AddHeader("Content-Range", "bytes */$length")
            return
        }
    }
    else {
        $response.StatusCode = 200
        $response.AddHeader("Accept-Ranges", "bytes")
    }

    $response.ContentType = Get-ContentType $path
    $response.ContentLength64 = $end - $start + 1

    $stream = [IO.File]::OpenRead($path)
    try {
        $stream.Seek($start, [IO.SeekOrigin]::Begin) | Out-Null
        $buffer = New-Object byte[] 65536
        $remaining = $response.ContentLength64
        while ($remaining -gt 0) {
            $readSize = [Math]::Min($buffer.Length, $remaining)
            $read = $stream.Read($buffer, 0, $readSize)
            if ($read -le 0) { break }
            $response.OutputStream.Write($buffer, 0, $read)
            $remaining -= $read
        }
    }
    finally {
        $stream.Dispose()
    }
}

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response

        try {
            $path = [System.Uri]::UnescapeDataString($request.Url.AbsolutePath)

            if ($path -eq "/api/media") {
                $files = @(Get-ChildItem -Path $imagesDir -File |
                    Where-Object { $allowedMediaExt -contains $_.Extension.ToLowerInvariant() } |
                    Sort-Object Name |
                    Select-Object -ExpandProperty Name)

                Write-JsonResponse $response @{ files = $files }
            }
            else {
                $relative = if ($path -eq "/") { "index.html" } else { $path.TrimStart('/') }
                $relative = $relative -replace '/', [IO.Path]::DirectorySeparatorChar
                $fullPath = [IO.Path]::GetFullPath((Join-Path $root $relative))

                if (-not $fullPath.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $response.StatusCode = 403
                }
                else {
                    Write-FileResponse $request $response $fullPath
                }
            }
        }
        catch {
            $response.StatusCode = 500
            $message = [Text.Encoding]::UTF8.GetBytes("Server error")
            $response.OutputStream.Write($message, 0, $message.Length)
        }
        finally {
            $response.OutputStream.Close()
        }
    }
}
finally {
    $listener.Stop()
    $listener.Close()
}
