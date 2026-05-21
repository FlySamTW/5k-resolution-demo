@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul
cd /d "%~dp0"

set "BASE=%~dp0"
set "URL="

start "5K PrintScreen Watcher" /min powershell -STA -NoProfile -ExecutionPolicy Bypass -File "%BASE%watch-printscreen.ps1"

call :CheckRunning 8899
if defined URL goto :OpenBrowser
call :CheckRunning 8900
if defined URL goto :OpenBrowser

call :StartAndWait 8899
if defined URL goto :OpenBrowser
call :StartAndWait 8900
if defined URL goto :OpenBrowser
call :StartAndWait 8910
if defined URL goto :OpenBrowser
call :StartAndWait 8920
if defined URL goto :OpenBrowser
call :StartAndWait 8930
if defined URL goto :OpenBrowser

echo [ERROR] Failed to start demo server on 8899/8900/8910/8920/8930.
echo Please run start-demo.ps1 manually and check error message.
pause
exit /b 1

:OpenBrowser
echo [OK] Demo server is ready at %URL%
start "" "%URL%/"
echo.
echo Browser opened. This launcher can be closed safely.
pause
exit /b 0

:CheckRunning
set "PORT=%~1"
powershell -NoProfile -Command "try { $expected=(Resolve-Path -LiteralPath $env:BASE).Path; $info=Invoke-RestMethod -Uri 'http://localhost:%PORT%/api/app-root' -TimeoutSec 1; if ($info.root -eq $expected) { exit 0 } else { exit 1 } } catch { exit 1 }"
if %errorlevel%==0 set "URL=http://localhost:%PORT%"
exit /b 0

:StartAndWait
set "PORT=%~1"
start "5K Demo Server %PORT%" powershell -NoExit -NoProfile -ExecutionPolicy Bypass -File "%BASE%start-demo.ps1" -Port %PORT%
for /l %%i in (1,1,5) do (
	powershell -NoProfile -Command "try { $expected=(Resolve-Path -LiteralPath $env:BASE).Path; $info=Invoke-RestMethod -Uri 'http://localhost:%PORT%/api/app-root' -TimeoutSec 1; if ($info.root -eq $expected) { exit 0 } else { exit 1 } } catch { exit 1 }"
	if !errorlevel!==0 (
		set "URL=http://localhost:%PORT%"
		exit /b 0
	)
	powershell -NoProfile -Command "Start-Sleep -Milliseconds 400"
)
exit /b 0
