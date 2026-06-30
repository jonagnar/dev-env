# tests/restore.Tests.ps1
BeforeAll {
    . "$PSScriptRoot/../scripts/restore.ps1"
}

Describe "Invoke-Restore" {
    BeforeEach {
        Mock Invoke-Native { }
        Mock Get-LatestArchive { "$TestDrive/backups/dev-backup-x.tar.age" }
        Mock Test-Path { $true }
        Mock New-Item { }
    }
    It "does nothing under -WhatIf" {
        Invoke-Restore -WhatIf
        Should -Invoke Invoke-Native -Times 0
    }
    It "decrypts then extracts to a staging dir" {
        Invoke-Restore -Yes
        Should -Invoke Invoke-Native -ParameterFilter { $File -eq 'age' -and $Arguments -contains '-d' }
        Should -Invoke Invoke-Native -ParameterFilter { $File -eq 'tar' -and $Arguments -contains '-xf' }
    }
}
