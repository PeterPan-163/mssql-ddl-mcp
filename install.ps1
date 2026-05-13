#Requires -Version 5.1
<#
.SYNOPSIS
    Installs the arcerp + arcerp_ddl MCP server entries into a Cowork / Claude
    Desktop config.

.DESCRIPTION
    Adds two MCP entries to %APPDATA%\Claude\claude_desktop_config.json:
      - arcerp     (read/write/list via @executeautomation/database-server)
      - arcerp_ddl (whitelisted DDL via @peterpan163/mssql-ddl-mcp)

    Prompts for the SQL Server password securely if not provided. Backs up
    the existing config before modifying it. Verifies Node.js is installed.

.PARAMETER MssqlServer
    SQL Server host. Default: 40.90.226.68.

.PARAMETER MssqlPort
    SQL Server port. Default: 1433.

.PARAMETER MssqlDatabase
    Database name. Default: arcerp_qa.

.PARAMETER MssqlUser
    SQL login. Default: dev.

.PARAMETER MssqlPassword
    SQL password as a SecureString. If omitted, prompts securely.

.PARAMETER ConfigPath
    Path to claude_desktop_config.json. Defaults to
    %APPDATA%\Claude\claude_desktop_config.json.

.PARAMETER DdlPackageVersion
    Version of @peterpan163/mssql-ddl-mcp to pin. Default: 0.1.1.

.EXAMPLE
    .\install.ps1

.EXAMPLE
    .\install.ps1 -MssqlDatabase arcerp_prod
#>

[CmdletBinding()]
param(
    [string]$MssqlServer = "40.90.226.68",
    [string]$MssqlPort = "1433",
    [string]$MssqlDatabase = "arcerp_qa",
    [string]$MssqlUser = "dev",
    [SecureString]$MssqlPassword,
    [string]$ConfigPath = (Join-Path $env:APPDATA "Claude\claude_desktop_config.json"),
    [string]$DdlPackageVersion = "0.1.1"
)

$ErrorActionPreference = "Stop"

function Write-Step($msg) {
    Write-Host ""
    Write-Host "==> $msg" -ForegroundColor Cyan
}

function Write-Ok($msg) {
    Write-Host "    $msg" -ForegroundColor Green
}

function Write-Warn($msg) {
    Write-Host "    $msg" -ForegroundColor Yellow
}

# --- 1. Verify Node.js ---
Write-Step "Checking for Node.js"
$nodeVersion = $null
try {
    $nodeVersion = (node --version) 2>$null
} catch {}
if (-not $nodeVersion) {
    Write-Host "    Node.js is not installed or not on PATH." -ForegroundColor Red
    Write-Host "    Install via either:" -ForegroundColor Yellow
    Write-Host "      winget install OpenJS.NodeJS"
    Write-Host "      https://nodejs.org/  (download LTS)"
    exit 1
}
Write-Ok "Node.js $nodeVersion"

# --- 2. Get password ---
Write-Step "SQL Server credentials"
Write-Host "    Server:   $MssqlServer`:$MssqlPort"
Write-Host "    Database: $MssqlDatabase"
Write-Host "    User:     $MssqlUser"

if (-not $MssqlPassword) {
    $MssqlPassword = Read-Host "    Password" -AsSecureString
}

$bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($MssqlPassword)
$plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

# --- 3. Ensure config directory exists ---
Write-Step "Locating MCP config"
$configDir = Split-Path $ConfigPath -Parent
if (-not (Test-Path $configDir)) {
    Write-Warn "Config directory does not exist; creating it: $configDir"
    New-Item -ItemType Directory -Path $configDir -Force | Out-Null
}
Write-Ok "$ConfigPath"

# --- 4. Load or initialize config ---
$config = $null
if (Test-Path $ConfigPath) {
    Write-Step "Backing up existing config"
    $backupPath = "$ConfigPath.bak.$(Get-Date -Format 'yyyyMMddHHmmss')"
    Copy-Item $ConfigPath $backupPath
    Write-Ok "Backup: $backupPath"

    try {
        $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json -AsHashtable
    } catch {
        Write-Warn "Could not parse existing config; starting fresh."
        $config = $null
    }
}
if (-not $config) {
    $config = @{}
}
if (-not $config.mcpServers) {
    $config.mcpServers = @{}
}

# --- 5. Add entries ---
Write-Step "Adding MCP entries"

if ($config.mcpServers.ContainsKey("arcerp")) {
    Write-Warn "Replacing existing 'arcerp' entry."
}
$config.mcpServers["arcerp"] = @{
    command = "npx"
    args    = @(
        "-y",
        "@executeautomation/database-server",
        "--sqlserver",
        "--server",   $MssqlServer,
        "--port",     $MssqlPort,
        "--database", $MssqlDatabase,
        "--user",     $MssqlUser,
        "--password", $plainPassword
    )
}
Write-Ok "arcerp (read/write/list/describe)"

if ($config.mcpServers.ContainsKey("arcerp_ddl")) {
    Write-Warn "Replacing existing 'arcerp_ddl' entry."
}
$config.mcpServers["arcerp_ddl"] = @{
    command = "npx"
    args    = @("-y", "@peterpan163/mssql-ddl-mcp@$DdlPackageVersion")
    env     = @{
        MSSQL_SERVER   = $MssqlServer
        MSSQL_PORT     = $MssqlPort
        MSSQL_DATABASE = $MssqlDatabase
        MSSQL_USER     = $MssqlUser
        MSSQL_PASSWORD = $plainPassword
    }
}
Write-Ok "arcerp_ddl (whitelisted DDL)"

# --- 6. Write config ---
Write-Step "Writing config"
$json = $config | ConvertTo-Json -Depth 10
Set-Content -Path $ConfigPath -Value $json -Encoding UTF8
Write-Ok "Saved."

# --- 7. Clear plaintext password ---
$plainPassword = $null
[System.GC]::Collect()

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Quit Cowork / Claude Desktop completely (right-click tray icon -> Quit)."
Write-Host "  2. Reopen it."
Write-Host "  3. You should see two new MCP toolsets:"
Write-Host "       mcp__arcerp__*           (SELECT/INSERT/UPDATE/DELETE, list tables, describe)"
Write-Host "       mcp__arcerp_ddl__ddl_query  (whitelisted CREATE/DROP INDEX, CREATE/ALTER/DROP VIEW)"
Write-Host ""
