#requires -Version 7
<#
.SYNOPSIS  Provision or refresh this machine for the meta-repo dev-environment.
.EXAMPLE   ./scripts/init.ps1 -WhatIf    # preview
.EXAMPLE   ./scripts/init.ps1            # provision
#>
param([switch]$WhatIf, [switch]$Yes, [switch]$Help)

. "$PSScriptRoot/lib/common.ps1"
. "$PSScriptRoot/verify.ps1"   # provides Invoke-Verify for Phase 6

function Test-HasCommand {
    param([Parameter(Mandatory)][string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Install-Scoop {
    # Bootstrap scoop per-user (NO admin), mirroring init.sh's ensure_mise.
    # Must run non-elevated: scoop refuses to install in an elevated shell.
    Invoke-Native -File 'pwsh' -Arguments @(
        '-NoProfile', '-Command',
        'Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression'
    )
    # The installer only edits the persisted user PATH; expose scoop's shims to
    # the REST of this process so the following `scoop install` resolves.
    $shims = Join-Path $HOME 'scoop/shims'
    if (Test-Path $shims) {
        $env:PATH = $shims + [IO.Path]::PathSeparator + $env:PATH
    }
}

function New-DevAgeKey {
    param([string]$KeyPath, [string]$SopsTemplate, [string]$SopsConfig)
    $dir = Split-Path -Parent $KeyPath
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    # Lock the key directory to the current user BEFORE writing the key (no inheritable window).
    if ($IsWindows) {
        $me = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        Invoke-Native -File 'icacls' -Arguments @($dir, '/inheritance:r', '/grant:r', "${me}:(OI)(CI)F")
    }
    if (-not (Test-Path $KeyPath)) {
        Invoke-Native -File 'age-keygen' -Arguments @('-o', $KeyPath)
    }
    # Render the gitignored .sops.yaml from the tracked template with this machine's PUBLIC key.
    $pub = "$( Invoke-Native -File 'age-keygen' -Arguments @('-y', $KeyPath) )".Trim()
    (Get-Content $SopsTemplate -Raw) -replace 'REPLACE_WITH_AGE_PUBLIC_KEY', $pub |
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
    # No admin required (mirrors init.sh's no-root design). scoop is a per-user
    # package manager that refuses to run in an elevated shell, so requiring
    # admin would actively block the scoop bootstrap in Phase 1.
    if (-not (Test-HasCommand 'git')) {
        Write-Warn "git not found — scoop will install it in Phase 1."
    }
    $distro = Get-WslDistro
    if ($distro) { Write-Info "WSL distro detected: $distro" } else { Write-Warn "No WSL distro found (ok for Windows-only use)." }

    Write-Phase "Phase 1 — Tools"
    Invoke-Step -Name "bootstrap scoop (per-user, if missing)" -Action {
        if (Test-HasCommand 'scoop') { Write-Info "scoop already present." }
        else { Install-Scoop }
    }
    Invoke-Step -Name "scoop install git mise" -Action {
        Invoke-Native -File 'scoop' -Arguments @('install', 'git', 'mise')
    }
    Invoke-Step -Name "mise install core (sops age chezmoi gitleaks)" -Action {
        $cfg = Join-Path $root '.config/mise/core.toml'
        $env:MISE_GLOBAL_CONFIG_FILE = $cfg
        Invoke-Native -File 'mise' -Arguments @('trust', $cfg)
        Invoke-Native -File 'mise' -Arguments @('install')
    }
    # Put the just-installed mise tools on PATH for the rest of THIS process —
    # chezmoi (Phase 3), age-keygen (Phase 4) and verify (Phase 6) run here,
    # before any new shell activates mise.
    if (-not $script:DryRun -and (Get-Command mise -ErrorAction SilentlyContinue)) {
        $env:MISE_GLOBAL_CONFIG_FILE = Join-Path $root '.config/mise/core.toml'
        try { mise env -s pwsh | Out-String | Invoke-Expression } catch { }
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
        New-DevAgeKey -KeyPath (Get-AgeKeyPath) `
            -SopsTemplate (Join-Path $root '.config/sops/.sops.yaml.tmpl') `
            -SopsConfig (Join-Path $root '.config/sops/.sops.yaml')
    }
    Write-Info "Store the PRIVATE key (~/.config/sops/age/keys.txt) in your password manager (Bitwarden/Vaultwarden) + offline."

    Write-Phase "Phase 5 — Schedule"
    Invoke-Step -Name "register daily catch-up backup task" -Action {
        Register-BackupTask -Root $root
    }

    Write-Phase "Phase 6 — Verify"
    if (-not $script:DryRun) { Invoke-Verify | Out-Null }
}

if ($Help) { Get-Help $PSCommandPath -Detailed; return }
if ($MyInvocation.InvocationName -ne '.') { Invoke-Init -WhatIf:$WhatIf -Yes:$Yes }
