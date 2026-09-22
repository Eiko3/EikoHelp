@echo off
setlocal
cd /d "%~dp0"
set PYTHONUTF8=1

REM If the server is already running, just open the admin page.
curl -s -o nul --max-time 2 http://localhost:8000/admin
if not errorlevel 1 (
    echo Server already running. Opening admin page...
    start "" http://localhost:8000/admin
    timeout /t 2 /nobreak >nul
    exit /b 0
)

where uv >nul 2>nul
if errorlevel 1 (
    echo [ERROR] uv not found in PATH. Please install uv first.
    pause
    exit /b 1
)

echo ================================================
echo   EikoHelp - starting server on port 8000 ...
echo   Browser will open at http://localhost:8000/admin
echo   Keep this window open. Close it to STOP.
echo ================================================

start "" /min cmd /c "timeout /t 8 /nobreak >nul & start http://localhost:8000/admin"

uv run python -m uvicorn app.main:app --port 8000

echo.
echo Server stopped.
pause
