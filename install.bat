@echo off
title MSSQL MCP Installer
setlocal

echo.
echo  ============================================================
echo   MSSQL MCP Installer
echo   Adds the arcerp + arcerp_ddl entries to your Cowork config.
echo  ============================================================
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "iwr -useb https://raw.githubusercontent.com/PeterPan-163/mssql-ddl-mcp/main/install.ps1 | iex"

set ERR=%ERRORLEVEL%
echo.
if %ERR% NEQ 0 (
    echo  PowerShell exited with code %ERR%. Scroll up for error details.
) else (
    echo  Done. Quit and reopen Cowork / Claude Desktop to load the new MCP entries.
)
echo.
echo  Press any key to close this window.
REM Read from CON: directly so we don't see EOF from a closed stdin.
pause >nul <con
