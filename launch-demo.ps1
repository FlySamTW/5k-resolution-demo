$ErrorActionPreference = "SilentlyContinue"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$ports = @(18765, 18766, 18767, 18768, 18769)

function Test-SameApp([int]$Port) {
    try {
        $info = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/api/app-root" -TimeoutSec 1
        return ($info.root -eq $root)
    }
    catch {
        return $false
    }
}

foreach ($port in $ports) {
    if (Test-SameApp $port) {
        Start-Process "http://127.0.0.1:$port/"
        Write-Host "Demo opened: http://127.0.0.1:$port/" -ForegroundColor Green
        exit 0
    }
}

foreach ($port in $ports) {
    Start-Process powershell -WindowStyle Minimized -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        "`"$root\start-demo.ps1`"",
        "-Port",
        "$port"
    ) | Out-Null

    for ($i = 0; $i -lt 10; $i++) {
        Start-Sleep -Milliseconds 350
        if (Test-SameApp $port) {
            Start-Process "http://127.0.0.1:$port/"
            Write-Host "Demo opened: http://127.0.0.1:$port/" -ForegroundColor Green
            exit 0
        }
    }
}

Write-Host "Failed to start demo server." -ForegroundColor Red
Write-Host "Please close old demo server windows and try again." -ForegroundColor Yellow
Read-Host "Press Enter to close"
exit 1
