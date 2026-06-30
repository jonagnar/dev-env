# scripts/lib/common.ps1
# Shared contract dot-sourced by every verb. Callers set $script:DryRun and
# $script:AssumeYes before invoking the helpers (defaults below cover tests).
if ($null -eq $script:DryRun)    { $script:DryRun = $false }
if ($null -eq $script:AssumeYes) { $script:AssumeYes = $false }

function Write-Info  { param([string]$Message) Write-Host $Message -ForegroundColor Gray }
function Write-Warn  { param([string]$Message) Write-Host "WARN: $Message" -ForegroundColor Yellow }
function Write-Err   { param([string]$Message) Write-Host "ERROR: $Message" -ForegroundColor Red }
function Write-Phase { param([string]$Message) Write-Host "`n== $Message ==" -ForegroundColor White }

function Invoke-Native {
    param(
        [Parameter(Mandatory)][string]$File,
        [string[]]$Arguments = @()
    )
    & $File @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed (exit $LASTEXITCODE): $File $($Arguments -join ' ')"
    }
}

function Invoke-Step {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Action,
        [switch]$Always   # run even under dry-run (read-only steps)
    )
    if ($script:DryRun -and -not $Always) {
        Write-Host ("  [dry-run] would: {0}" -f $Name) -ForegroundColor DarkGray
        return
    }
    Write-Host ("  -> {0}" -f $Name) -ForegroundColor Cyan
    & $Action
}
