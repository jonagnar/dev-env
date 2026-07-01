#requires -Version 7
<# .SYNOPSIS  Pull the meta-repo, reconcile tools to the core config, re-apply host config. #>
param([switch]$WhatIf, [switch]$Yes, [switch]$Help)

. "$PSScriptRoot/lib/common.ps1"
. "$PSScriptRoot/verify.ps1"   # for Invoke-Verify

function Invoke-Update {
    param([switch]$WhatIf, [switch]$Yes)
    $script:DryRun = [bool]$WhatIf
    $script:AssumeYes = [bool]$Yes
    $root = Get-DevRoot

    Write-Phase "Update"
    Invoke-Step -Name "git pull meta-repo" -Action {
        try { Invoke-Native -File 'git' -Arguments @('-C', $root, 'pull', '--ff-only') }
        catch { Write-Warn "git pull failed (continuing): $($_.Exception.Message)" }
    }

    if (Confirm-Action -Message "Update installed tools (scoop + mise)?") {
        Invoke-Step -Name "reconcile mise tools" -Action {
            $env:MISE_GLOBAL_CONFIG_FILE = Join-Path $root '.config/mise/core.toml'
            Invoke-Native -File 'mise' -Arguments @('install')
            Invoke-Native -File 'mise' -Arguments @('upgrade')
        }
        Invoke-Step -Name "scoop update" -Action {
            Invoke-Native -File 'scoop' -Arguments @('update', '*')
        }
    } else {
        Write-Warn "Skipped tool updates."
    }

    Invoke-Step -Name "re-apply chezmoi" -Action {
        $env:DEV_ROOT = $root
        Invoke-Native -File 'chezmoi' -Arguments @('apply', '--source', (Join-Path $root '.config/chezmoi'))
    }

    if (-not $script:DryRun) { Invoke-Verify | Out-Null }
}

if ($Help) { Get-Help $PSCommandPath -Detailed; return }
if ($MyInvocation.InvocationName -ne '.') { Invoke-Update -WhatIf:$WhatIf -Yes:$Yes }
