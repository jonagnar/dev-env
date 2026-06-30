# tests/bash-scaffold.Tests.ps1
Describe "bash scaffolds" {
    It "every verb .sh exists and exits non-zero with a not-implemented message" {
        foreach ($v in @('init','verify','update','backup','restore')) {
            $path = "$PSScriptRoot/../scripts/$v.sh"
            Test-Path $path | Should -BeTrue
            $out = bash $path 2>&1
            $LASTEXITCODE | Should -Not -Be 0
            ($out -join "`n") | Should -Match 'not yet implemented'
        }
    }
}
