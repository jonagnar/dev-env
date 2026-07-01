#requires -Version 7
<# .SYNOPSIS  Produce an age-encrypted snapshot of all repos into backups/. #>
param([switch]$WhatIf, [switch]$Yes, [string]$BackupDir, [switch]$Help)

. "$PSScriptRoot/lib/common.ps1"

function Get-DevRepos {
    param([string]$Root)
    $repos = @()
    if (Test-Path (Join-Path $Root '.git')) { $repos += $Root }
    $opsDir = Join-Path $Root 'ops'
    if (Test-Path $opsDir) {
        Get-ChildItem $opsDir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            if (Test-Path (Join-Path $_.FullName '.git')) { $repos += $_.FullName }
        }
    }
    return $repos
}

function Get-BackupRecipients {
    param([string]$Root)
    $sops = Join-Path $Root '.config/sops/.sops.yaml'
    if (-not (Test-Path $sops)) { throw "No .config/sops/.sops.yaml found — run init first." }
    $line = Get-Content $sops | Where-Object { $_ -match '^\s*age:' } | Select-Object -First 1
    if (-not $line) { throw ".sops.yaml has no 'age:' recipient." }
    $val = ($line -replace '^\s*age:\s*', '').Trim().Trim('"', "'")
    return ($val -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Invoke-Backup {
    param([switch]$WhatIf, [switch]$Yes, [string]$BackupDir)
    $script:DryRun = [bool]$WhatIf
    $script:AssumeYes = [bool]$Yes
    $root = Get-DevRoot
    if (-not $BackupDir) { $BackupDir = Join-Path $root 'backups' }

    $stamp = (Get-Date -Format 'yyyyMMdd-HHmmss')
    $staging = Join-Path ([IO.Path]::GetTempPath()) "devbackup-$stamp"
    $tar = Join-Path $BackupDir "dev-backup-$stamp.tar"
    $enc = "$tar.age"
    $keyPath = Get-AgeKeyPath

    Write-Phase "Backup -> $enc"
    Invoke-Step -Name "bundle repos" -Action {
        New-Item -ItemType Directory -Force -Path $staging | Out-Null
        foreach ($repo in (Get-DevRepos -Root $root)) {
            $name = Split-Path $repo -Leaf
            Invoke-Native -File 'git' -Arguments @('-C', $repo, 'bundle', 'create', (Join-Path $staging "$name.bundle"), '--all')
        }
    }
    Invoke-Step -Name "tar staging" -Action {
        if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null }
        Invoke-Native -File 'tar' -Arguments @('-cf', $tar, '-C', $staging, '.')
    }
    Invoke-Step -Name "age-encrypt + clean up" -Action {
        try {
            $recipients = Get-BackupRecipients -Root $root
            if (-not $recipients) { throw ".sops.yaml has no age recipient — refusing to leave plaintext behind." }
            $ageArgs = @()
            foreach ($r in $recipients) { $ageArgs += @('-r', $r) }
            $ageArgs += @('-o', $enc, $tar)
            Invoke-Native -File 'age' -Arguments $ageArgs
        } finally {
            # Always shred the plaintext tar + staging, on success OR failure:
            # the synced backups/ dir must never retain a plaintext archive
            # (the repo's headline invariant is "provider only sees ciphertext").
            Remove-Item $tar -Force -ErrorAction SilentlyContinue
            Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    if ($script:DryRun) {
        Write-Info "[dry-run] would write backup: $enc"
    } else {
        Write-Info "Backup written: $enc"
    }
}

if ($Help) { Get-Help $PSCommandPath -Detailed; return }
if ($MyInvocation.InvocationName -ne '.') { Invoke-Backup -WhatIf:$WhatIf -Yes:$Yes -BackupDir:$BackupDir }
