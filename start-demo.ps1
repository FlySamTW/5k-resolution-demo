param(
    [int]$Port = 18765
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$imagesDir = Join-Path $root "images"
if (-not (Test-Path $imagesDir)) {
    New-Item -Path $imagesDir -ItemType Directory | Out-Null
}

$allowedMediaExt = @(".png", ".jpg", ".jpeg", ".webp", ".mp4", ".webm", ".mkv")

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
        ".mkv" { "video/x-matroska" }
        default { "application/octet-stream" }
    }
}

function Write-Response($stream, [int]$status, [hashtable]$headers, [byte[]]$body) {
    if ($null -eq $body) { $body = [byte[]]@() }
    $reason = switch ($status) {
        200 { "OK" }
        206 { "Partial Content" }
        403 { "Forbidden" }
        404 { "Not Found" }
        416 { "Range Not Satisfiable" }
        500 { "Server Error" }
        default { "OK" }
    }
    $headers["Content-Length"] = $body.Length
    $headers["Connection"] = "close"
    $headerText = "HTTP/1.1 $status $reason`r`n"
    foreach ($key in $headers.Keys) {
        $headerText += "$key`: $($headers[$key])`r`n"
    }
    $headerText += "`r`n"
    $headerBytes = [Text.Encoding]::ASCII.GetBytes($headerText)
    $stream.Write($headerBytes, 0, $headerBytes.Length)
    if ($body.Length -gt 0) {
        $stream.Write($body, 0, $body.Length)
    }
}

function Write-JsonResponse($stream, $obj) {
    $json = $obj | ConvertTo-Json -Depth 8 -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    Write-Response $stream 200 @{
        "Content-Type" = "application/json; charset=utf-8"
        "Cache-Control" = "no-store"
    } $bytes
}

function Write-TextResponse($stream, [int]$status, [string]$text) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($text)
    Write-Response $stream $status @{ "Content-Type" = "text/plain; charset=utf-8" } $bytes
}

function Write-FileResponse($stream, [string]$path, [hashtable]$headers) {
    if (-not (Test-Path $path -PathType Leaf)) {
        Write-TextResponse $stream 404 "Not found"
        return
    }

    $file = Get-Item -LiteralPath $path
    $length = [int64]$file.Length
    $start = [int64]0
    $end = [int64]($length - 1)
    $status = 200
    $responseHeaders = @{
        "Content-Type" = Get-ContentType $path
        "Accept-Ranges" = "bytes"
        "Cache-Control" = $(if ([IO.Path]::GetFileName($path) -eq "index.html") { "no-store" } else { "public, max-age=3600" })
    }

    if ($headers.ContainsKey("range") -and $headers["range"] -match "^bytes=(\d*)-(\d*)$") {
        if ($matches[1]) { $start = [int64]$matches[1] }
        if ($matches[2]) { $end = [int64]$matches[2] }
        if ($start -gt $end -or $end -ge $length) {
            Write-Response $stream 416 @{ "Content-Range" = "bytes */$length" } ([byte[]]@())
            return
        }
        $status = 206
        $responseHeaders["Content-Range"] = "bytes $start-$end/$length"
    }

    $count = [int]($end - $start + 1)
    $buffer = New-Object byte[] $count
    $fileStream = [IO.File]::OpenRead($path)
    try {
        $fileStream.Seek($start, [IO.SeekOrigin]::Begin) | Out-Null
        $offset = 0
        while ($offset -lt $count) {
            $read = $fileStream.Read($buffer, $offset, $count - $offset)
            if ($read -le 0) { break }
            $offset += $read
        }
        if ($offset -ne $count) {
            $buffer = $buffer[0..($offset - 1)]
        }
    }
    finally {
        $fileStream.Dispose()
    }

    Write-Response $stream $status $responseHeaders $buffer
}

function Read-Request($stream) {
    $reader = New-Object IO.StreamReader($stream, [Text.Encoding]::ASCII, $false, 8192, $true)
    $requestLine = $reader.ReadLine()
    if (-not $requestLine) { return $null }
    $parts = $requestLine.Split(" ")
    if ($parts.Length -lt 2) { return $null }

    $headers = @{}
    while ($true) {
        $line = $reader.ReadLine()
        if ($null -eq $line -or $line -eq "") { break }
        $colon = $line.IndexOf(":")
        if ($colon -gt 0) {
            $headers[$line.Substring(0, $colon).Trim().ToLowerInvariant()] = $line.Substring($colon + 1).Trim()
        }
    }

    return @{
        Method = $parts[0].ToUpperInvariant()
        Path = [Uri]::UnescapeDataString($parts[1].Split("?")[0])
        Headers = $headers
    }
}

function Handle-Request($stream, $request) {
    $path = $request.Path

    if ($path -eq "/api/media") {
        $files = @(Get-ChildItem -Path $imagesDir -File |
            Where-Object { $allowedMediaExt -contains $_.Extension.ToLowerInvariant() } |
            Sort-Object Name |
            ForEach-Object {
                @{
                    name = $_.Name
                    src = "images/$([uri]::EscapeDataString($_.Name))"
                    modifiedAt = ([DateTimeOffset]$_.LastWriteTimeUtc).ToUnixTimeMilliseconds()
                }
            })
        Write-JsonResponse $stream @{ files = $files }
        return
    }

    if ($path -eq "/api/app-root") {
        Write-JsonResponse $stream @{ root = $root }
        return
    }

    $relative = if ($path -eq "/") { "index.html" } else { $path.TrimStart("/") }
    $relative = $relative -replace "/", [IO.Path]::DirectorySeparatorChar
    $fullPath = [IO.Path]::GetFullPath((Join-Path $root $relative))

    if (-not $fullPath.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
        Write-TextResponse $stream 403 "Forbidden"
        return
    }

    Write-FileResponse $stream $fullPath $request.Headers
}

$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $Port)
try {
    $listener.Start()
}
catch {
    Write-Host "Port $Port is unavailable. Trying next port from launcher..." -ForegroundColor Yellow
    exit 2
}

Write-Host "Demo server is running: http://127.0.0.1:$Port/" -ForegroundColor Green
Write-Host "Press Ctrl+C to stop the server." -ForegroundColor Yellow

try {
    while ($true) {
        $client = $listener.AcceptTcpClient()
        try {
            $stream = $client.GetStream()
            $request = Read-Request $stream
            if ($null -ne $request) {
                Handle-Request $stream $request
            }
        }
        catch {
            try {
                Write-TextResponse $stream 500 "Server error"
            }
            catch {}
        }
        finally {
            $client.Close()
        }
    }
}
finally {
    $listener.Stop()
}
