#requires -Version 7
<#
.SYNOPSIS  Provision or refresh this machine for the meta-repo dev-environment.
.EXAMPLE   ./scripts/init.ps1 -WhatIf    # preview
.EXAMPLE   ./scripts/init.ps1            # provision
#>
param([switch]$WhatIf, [switch]$Yes, [switch]$Help)

. "$PSScriptRoot/lib/common.ps1"
. "$PSScriptRoot/verify.ps1"   # provides Invoke-Verify for Phase 6

function New-DevAgeKey {
    param([string]$KeyPath, [string]$SopsConfig)
    $dir = Split-Path -Parent $KeyPath
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    if (-not (Test-Path $KeyPath)) {
        Invoke-Native -File 'age-keygen' -Arguments @('-o', $KeyPath)
        # lock down to current user, read-only
        if ($IsWindows -or $null -eq $IsWindows) {
            Invoke-Native -File 'icacls' -Arguments @($KeyPath, '/inheritance:r', '/grant:r', "$($env:USERNAME):(R)")
        }
    }
    $pub = "$( Invoke-Native -File 'age-keygen' -Arguments @('-y', $KeyPath) )".Trim()
    (Get-Content $SopsConfig -Raw) -replace 'REPLACE_WITH_AGE_PUBLIC_KEY', $pub |
        Set-Content $SopsConfig -NoNewline
}

function Register-BackupTask {
    param([string]$Root)
    $script = Join-Path $Root 'scripts/backup.ps1'
    $action = New-ScheduledTaskAction -Execute 'pwsh.exe' `
        -Argument "-NoProfile -File `"$script`" -Yes"
    $trigger = New-ScheduledTaskTrigger -Daily -At '13:00'
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable
    Register-ScheduledTask -TaskName 'devenv-backup' -Action $action -Trigger $trigger `
        -Settings $settings -Force | Out-Null
}

function Invoke-Init {
    param([switch]$WhatIf, [switch]$Yes)
    $script:DryRun = [bool]$WhatIf
    $script:AssumeYes = [bool]$Yes
    $root = Get-DevRoot

    Write-Phase "Phase 0 — Preflight"
    if (-not (Test-Admin)) {
        throw "init must run as administrator. Re-open your terminal with 'Run as administrator' and try again."
    }
    $distro = Get-WslDistro
    if ($distro) { Write-Info "WSL distro detected: $distro" } else { Write-Warn "No WSL distro found (ok for Windows-only use)." }

    Write-Phase "Phase 1 — Tools"
    Invoke-Step -Name "scoop install git mise" -Action {
        Invoke-Native -File 'scoop' -Arguments @('install', 'git', 'mise')
    }
    Invoke-Step -Name "mise install core (sops age chezmoi gitleaks)" -Action {
        $env:MISE_GLOBAL_CONFIG_FILE = Join-Path $root '.config/mise/config.toml'
        Invoke-Native -File 'mise' -Arguments @('install')
    }

    Write-Phase "Phase 2 — Skeleton"
    foreach ($d in @('ops', 'tools/bin', 'backups')) {
        Invoke-Step -Name "ensure $d/" -Action {
            $p = Join-Path $root $d
            if (-not (Test-Path $p)) { New-Item -ItemType Directory -Force -Path $p | Out-Null }
        }
    }

    Write-Phase "Phase 3 — Host config"
    Invoke-Step -Name "chezmoi init --apply" -Action {
        $env:DEV_ROOT = $root
        Invoke-Native -File 'chezmoi' -Arguments @('init', '--apply', '--source', (Join-Path $root '.config/chezmoi'))
    }

    Write-Phase "Phase 4 — Secrets"
    Invoke-Step -Name "generate work age key + write recipient" -Action {
        New-DevAgeKey -KeyPath (Get-AgeKeyPath) -SopsConfig (Join-Path $root '.config/sops/.sops.yaml')
    }
    Write-Info "Store the PRIVATE key (~/.config/sops/age/keys.txt) in Vaultwarden + offline."

    Write-Phase "Phase 5 — Schedule"
    Invoke-Step -Name "register daily catch-up backup task" -Action {
        Register-BackupTask -Root $root
    }

    Write-Phase "Phase 6 — Verify"
    if (-not $script:DryRun) { Invoke-Verify | Out-Null }
}

if ($Help) { Get-Help $PSCommandPath -Detailed; return }
if ($MyInvocation.InvocationName -ne '.') { Invoke-Init -WhatIf:$WhatIf -Yes:$Yes }
