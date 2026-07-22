<#
.SYNOPSIS
    Set up and run the LangGraph AI Orchestrator locally.

.DESCRIPTION
    Creates a .venv (first run only), installs requirements, then runs the
    orchestrator. With no run args it starts the interactive REPL.

.EXAMPLE
    .\run.ps1                                  # interactive REPL
    .\run.ps1 "how many loan applications are there?"   # one-shot prompt
    .\run.ps1 --list-tools                     # print generated tools, no API calls
    .\run.ps1 -Server                          # start the FastAPI server (/docs)
#>
[CmdletBinding()]
param(
    [switch]$Server,
    [switch]$Reinstall,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Args
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
Set-Location $root

# --- Python check ------------------------------------------------------------
$python = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $python) { throw "Python 3.10+ not found on PATH. Install it and retry." }

# --- Virtual environment -----------------------------------------------------
$venv = Join-Path $root '.venv'
$venvPython = Join-Path $venv 'Scripts\python.exe'

if ($Reinstall -and (Test-Path $venv)) {
    Write-Host "Removing existing .venv ..." -ForegroundColor Yellow
    Remove-Item -Recurse -Force $venv
}

if (-not (Test-Path $venvPython)) {
    Write-Host "Creating virtual environment (.venv) ..." -ForegroundColor Cyan
    & $python -m venv $venv
    & $venvPython -m pip install --upgrade pip | Out-Null
    Write-Host "Installing requirements ..." -ForegroundColor Cyan
    & $venvPython -m pip install -r (Join-Path $root 'requirements.txt')
} else {
    Write-Host "Using existing .venv (pass -Reinstall to rebuild)." -ForegroundColor DarkGray
}

# --- .env check --------------------------------------------------------------
if (-not (Test-Path (Join-Path $root '.env'))) {
    Write-Warning ".env not found. Copy .env.example to .env and fill it in before running."
}

# --- Run ---------------------------------------------------------------------
if ($Server) {
    Write-Host "Starting HTTP server (Swagger UI at http://localhost:8000/docs) ..." -ForegroundColor Green
    & $venvPython -m langgraph_orchestrator.server
} else {
    & $venvPython -m langgraph_orchestrator @Args
}
