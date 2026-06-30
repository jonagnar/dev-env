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
