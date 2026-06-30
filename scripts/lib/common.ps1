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
    # Callers must use Invoke-Native (not bare &) inside $Action so non-zero
    # exit codes surface as exceptions.
    & $Action
}

function Confirm-Action {
    param([Parameter(Mandatory)][string]$Message)
    if ($script:AssumeYes) { return $true }
    if ($script:DryRun) {
        Write-Host ("  [dry-run] would prompt: {0}" -f $Message) -ForegroundColor DarkGray
        return $false
    }
    $answer = Read-Host "$Message [y/N]"
    return ($answer -match '^(y|yes)$')
}

function Test-Admin {
    if ($IsWindows -or $null -eq $IsWindows) {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($id)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    return ($(id -u) -eq 0)
}

function Get-DevRoot {
    # common.ps1 lives at <root>/scripts/lib/common.ps1
    return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "../.."))
}

function Get-WslDistro {
    try {
        $raw = & wsl.exe -l -q 2>$null
        $first = ($raw | ForEach-Object { ($_ -replace "`0", '').Trim() } |
                  Where-Object { $_ }) | Select-Object -First 1
        if ($first) { return $first }
    } catch { }
    return $null
}

function Get-AgeKeyPath {
    return (Join-Path $HOME ".config/sops/age/keys.txt")
}

function Reset-Checks { $script:Checks = @() }

function Add-Check {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][bool]$Ok, [string]$Detail = "")
    if ($null -eq $script:Checks) { $script:Checks = @() }
    $script:Checks += [pscustomobject]@{ Name = $Name; Ok = $Ok; Detail = $Detail }
}

function Write-CheckSummary {
    Write-Host "`nVerification:" -ForegroundColor White
    $failed = 0
    foreach ($c in $script:Checks) {
        if ($c.Ok) {
            Write-Host ("  [ok] {0}" -f $c.Name) -ForegroundColor Green
        } else {
            Write-Host ("  [!!] {0} - {1}" -f $c.Name, $c.Detail) -ForegroundColor Red
            $failed++
        }
    }
    Write-Host ""
    if ($failed -gt 0) { Write-Host "$failed check(s) failed." -ForegroundColor Red; return 1 }
    Write-Host "All checks passed." -ForegroundColor Green
    return 0
}
