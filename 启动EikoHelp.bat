@echo off
setlocal
cd /d "%~dp0"
set PYTHONUTF8=1

where uv >nul 2>nul
if errorlevel 1 (
    echo [ERROR] uv not found in PATH. Please install uv first.
    pause
    exit /b 1
)

echo ================================================
echo   EikoHelp - starting server on port 8000 ...
echo   Browser will open at http://localhost:8000
echo   Keep this window open. Close it to STOP.
echo ================================================

REM To also start the two MCP servers (ch08 dynamic tool discovery),
REM remove "REM" from the next two lines:
REM start "MCP-Logistics" /min cmd /c "uv run python mcp_servers/logistics_server.py"
REM start "MCP-Aftersales" /min cmd /c "uv run python mcp_servers/aftersales_server.py"

start "" /min cmd /c "timeout /t 8 /nobreak >nul & start http://localhost:8000"

uv run uvicorn app.main:app --port 8000

echo.
echo Server stopped.
pause
