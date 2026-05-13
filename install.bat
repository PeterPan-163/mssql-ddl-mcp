@echo off
REM ===========================================================================
REM  install.bat
REM  Installs the arcerp + arcerp_ddl MSSQL MCP entries into the Cowork /
REM  Claude Desktop config. Double-click this file to run.
REM
REM  Downloads and executes:
REM    https://raw.githubusercontent.com/PeterPan-163/mssql-ddl-mcp/main/install.ps1
REM
REM  Prompts securely for SQL Host, User, and Password.
REM  Uses defaults: port 1433, database arcerp_qa.
REM ===========================================================================

echo.
echo  Installing MSSQL MCP connectors (arcerp + arcerp_ddl)...
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "iwr -useb https://raw.githubusercontent.com/PeterPan-163/mssql-ddl-mcp/main/install.ps1 | iex"

echo.
echo  Done. Quit and reopen Cowork / Claude Desktop to load the new MCP entries.
echo.
pause
