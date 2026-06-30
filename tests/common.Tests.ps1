# tests/common.Tests.ps1
BeforeAll {
    . "$PSScriptRoot/../scripts/lib/common.ps1"
}

Describe "Invoke-Native" {
    It "throws when the command exits non-zero" {
        { Invoke-Native -File 'pwsh' -Arguments @('-NoProfile','-Command','exit 1') } |
            Should -Throw
    }
    It "succeeds when the command exits zero" {
        { Invoke-Native -File 'pwsh' -Arguments @('-NoProfile','-Command','exit 0') } |
            Should -Not -Throw
    }
}

Describe "Invoke-Step (dry-run)" {
    It "skips the action when DryRun is set" {
        $script:DryRun = $true
        $ran = $false
        Invoke-Step -Name "do thing" -Action { $script:ran = $true }
        $ran | Should -BeFalse
    }
    It "runs the action when DryRun is not set" {
        $script:DryRun = $false
        $script:ran = $false
        Invoke-Step -Name "do thing" -Action { $script:ran = $true }
        $ran | Should -BeTrue
    }
}

Describe "Confirm-Action" {
    It "returns true without prompting when AssumeYes is set" {
        $script:AssumeYes = $true
        Confirm-Action -Message "overwrite?" | Should -BeTrue
    }
    It "returns false under dry-run without prompting" {
        $script:AssumeYes = $false
        $script:DryRun = $true
        Confirm-Action -Message "overwrite?" | Should -BeFalse
        $script:DryRun = $false
    }
}

Describe "Checklist" {
    It "summarizes failures and returns exit code 1 when a check fails" {
        Reset-Checks
        Add-Check -Name "key present" -Ok $true
        Add-Check -Name "tools installed" -Ok $false -Detail "mise missing"
        Write-CheckSummary | Should -Be 1
    }
    It "returns exit code 0 when all checks pass" {
        Reset-Checks
        Add-Check -Name "key present" -Ok $true
        Write-CheckSummary | Should -Be 0
    }
}

Describe "Get-DevRoot" {
    It "resolves the repo root (parent of scripts/)" {
        $expected = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
        $actual   = [System.IO.Path]::GetFullPath((Get-DevRoot))
        $actual | Should -Be $expected
    }
}
