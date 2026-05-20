param(
    [int]$Port = 8899
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$imagesDir = Join-Path $root "images"
if (-not (Test-Path $imagesDir)) {
    New-Item -Path $imagesDir -ItemType Directory | Out-Null
}

$allowedMediaExt = @(".png", ".jpg", ".jpeg", ".webp", ".mp4")

$listener = New-Object System.Net.HttpListener
$prefix = "http://localhost:$Port/"
$listener.Prefixes.Add($prefix)
$listener.Start()

Write-Host "展示伺服器已啟動：$prefix" -ForegroundColor Green
Write-Host "按 Ctrl+C 可停止伺服器。" -ForegroundColor Yellow

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

function Write-FileResponse($response, [string]$path) {
    if (-not (Test-Path $path -PathType Leaf)) {
        $response.StatusCode = 404
        return
    }

    $bytes = [IO.File]::ReadAllBytes($path)
    $response.StatusCode = 200
    $response.ContentType = Get-ContentType $path
    $response.ContentLength64 = $bytes.Length
    $response.OutputStream.Write($bytes, 0, $bytes.Length)
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
                    Write-FileResponse $response $fullPath
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
