#requires -Version 7
<#
.SYNOPSIS  Run the PowerShell (Pester) test suite, guarding the Pester >=5 requirement.
.DESCRIPTION
  Windows ships Pester 3.4 by default, but these tests use Pester 5 syntax
  (which errors at discovery under v3). This bootstraps a modern Pester into
  CurrentUser scope if it's missing, then runs every *.Tests.ps1 under tests/.
  Mirrors tests/bash/run.sh.
.EXAMPLE   pwsh -ExecutionPolicy Bypass -File tests/run.ps1
#>
$ErrorActionPreference = 'Stop'

$have = Get-Module -ListAvailable Pester |
    Where-Object { $_.Version.Major -ge 5 } | Select-Object -First 1
if (-not $have) {
    Write-Host "Pester >=5 not found — installing into CurrentUser scope..." -ForegroundColor Yellow
    Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser -Force -SkipPublisherCheck
}

Import-Module Pester -MinimumVersion 5.0
$cfg = New-PesterConfiguration
$cfg.Run.Path = $PSScriptRoot
$cfg.Output.Verbosity = 'Detailed'
$cfg.Run.Exit = $true
Invoke-Pester -Configuration $cfg
