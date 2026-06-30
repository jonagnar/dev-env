#requires -Version 7
<# .SYNOPSIS  Decrypt a backups/*.tar.age archive and extract it to a staging dir. #>
param([switch]$WhatIf, [switch]$Yes, [string]$Archive, [string]$BackupDir, [switch]$Help)

. "$PSScriptRoot/lib/common.ps1"

function Get-LatestArchive {
    param([string]$BackupDir)
    Get-ChildItem (Join-Path $BackupDir 'dev-backup-*.tar.age') -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty FullName
}

function Invoke-Restore {
    param([switch]$WhatIf, [switch]$Yes, [string]$Archive, [string]$BackupDir)
    $script:DryRun = [bool]$WhatIf
    $script:AssumeYes = [bool]$Yes
    $root = Get-DevRoot
    if (-not $BackupDir) { $BackupDir = Join-Path $root 'backups' }
    if (-not $Archive)   { $Archive = Get-LatestArchive -BackupDir $BackupDir }
    if (-not $Archive)   { throw "No backups found in $BackupDir. Nothing to restore." }

    $stamp = (Get-Date -Format 'yyyyMMdd-HHmmss')
    $staging = Join-Path $root "restore-$stamp"
    $tar = Join-Path ([IO.Path]::GetTempPath()) "restore-$stamp.tar"
    $keyPath = Get-AgeKeyPath

    Write-Phase "Restore $Archive -> $staging"
    if (-not (Confirm-Action -Message "Restore '$Archive' into '$staging'?")) {
        Write-Warn "Aborted."; return
    }
    Invoke-Step -Name "decrypt archive" -Action {
        Invoke-Native -File 'age' -Arguments @('-d', '-i', $keyPath, '-o', $tar, $Archive)
    }
    Invoke-Step -Name "extract to staging" -Action {
        New-Item -ItemType Directory -Force -Path $staging | Out-Null
        Invoke-Native -File 'tar' -Arguments @('-xf', $tar, '-C', $staging)
        Remove-Item $tar -Force -ErrorAction SilentlyContinue
    }
    Write-Info "Restored bundles are in $staging. To rebuild a repo: git clone <name>.bundle <target>."
}

if ($Help) { Get-Help $PSCommandPath -Detailed; return }
if ($MyInvocation.InvocationName -ne '.') { Invoke-Restore -WhatIf:$WhatIf -Yes:$Yes -Archive:$Archive -BackupDir:$BackupDir }
