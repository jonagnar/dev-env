#requires -Version 7
<# .SYNOPSIS  Read-only health check of the dev-environment. #>
param([switch]$Help)

. "$PSScriptRoot/lib/common.ps1"

function Invoke-Verify {
    $root = Get-DevRoot
    Reset-Checks

    foreach ($tool in @('git', 'mise', 'sops', 'age', 'age-keygen', 'chezmoi', 'gitleaks')) {
        Add-Check -Name "tool: $tool" -Ok ([bool](Get-Command $tool -ErrorAction SilentlyContinue)) -Detail "not on PATH"
    }

    $keyPath = Get-AgeKeyPath
    Add-Check -Name "age key present" -Ok (Test-Path $keyPath) -Detail "$keyPath missing — run init"

    foreach ($d in @('ops', 'tools/bin', 'backups', 'infra')) {
        Add-Check -Name "folder: $d" -Ok (Test-Path (Join-Path $root $d)) -Detail "missing"
    }

    # age key round-trip: encrypt a probe to the public key, decrypt with the private key, compare.
    $roundtripOk = $false
    if (Test-Path $keyPath) {
        try {
            $probe = 'devenv-roundtrip-probe'
            $tmp = New-TemporaryFile
            Set-Content -Path $tmp -Value $probe -NoNewline
            $enc = "$tmp.age"
            $recipient = "$( Invoke-Native -File 'age-keygen' -Arguments @('-y', $keyPath) )".Trim()
            Invoke-Native -File 'age' -Arguments @('-r', $recipient, '-o', $enc, $tmp) | Out-Null
            $decrypted = "$( Invoke-Native -File 'age' -Arguments @('-d', '-i', $keyPath, $enc) )".Trim()
            $roundtripOk = ($decrypted -eq $probe)
            Remove-Item $tmp, $enc -Force -ErrorAction SilentlyContinue
        } catch { $roundtripOk = $false }
    }
    Add-Check -Name "age key round-trip" -Ok $roundtripOk -Detail "encrypt/decrypt failed — key may be wrong"

    $taskOk = [bool](Get-ScheduledTask -TaskName 'devenv-backup' -ErrorAction SilentlyContinue)
    Add-Check -Name "backup task registered" -Ok $taskOk -Detail "devenv-backup not found — run init"

    return (Write-CheckSummary)
}

if ($Help) { Get-Help $PSCommandPath -Detailed; return }
if ($MyInvocation.InvocationName -ne '.') { exit (Invoke-Verify) }
