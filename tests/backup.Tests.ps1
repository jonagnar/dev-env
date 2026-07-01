# tests/backup.Tests.ps1
BeforeAll {
    . "$PSScriptRoot/../scripts/backup.ps1"
}

Describe "Invoke-Backup" {
    BeforeEach {
        Mock Invoke-Native { }
        Mock Get-DevRepos { @("$TestDrive/meta", "$TestDrive/ops/demo-api") }
        Mock Get-BackupRecipients { @('age1fakeRecipient') }
        Mock Test-Path { $true }
    }
    It "does nothing destructive under -WhatIf" {
        Invoke-Backup -WhatIf
        Should -Invoke Invoke-Native -Times 0
    }
    It "bundles each repo and age-encrypts the archive" {
        Invoke-Backup -Yes
        Should -Invoke Invoke-Native -ParameterFilter { $File -eq 'git' -and $Arguments -contains 'bundle' }
        Should -Invoke Invoke-Native -ParameterFilter { $File -eq 'age' }
    }
}

Describe "Invoke-Backup encryption failure" {
    It "never leaves a plaintext tar in backups/ when encryption fails" {
        $backupDir = Join-Path $TestDrive 'backups'
        New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
        Mock Get-DevRepos { @("$TestDrive/meta") }
        Mock Get-BackupRecipients { @('age1fakeRecipient') }
        # bundle + tar succeed (tar writes a real plaintext archive); age throws.
        Mock Invoke-Native {
            if ($File -eq 'tar') {
                $out = $Arguments | Where-Object { $_ -like '*.tar' } | Select-Object -First 1
                Set-Content -Path $out -Value 'PLAINTEXT' -NoNewline
                return
            }
            if ($File -eq 'age') { throw "encryption failed" }
        }
        { Invoke-Backup -Yes -BackupDir $backupDir } | Should -Throw
        (Get-ChildItem $backupDir -Filter '*.tar' -File) | Should -BeNullOrEmpty
    }
}

Describe "Get-DevRepos" {
    It "finds the meta-repo and git repos under ops/" {
        New-Item -ItemType Directory -Force -Path "$TestDrive/.git" | Out-Null
        New-Item -ItemType Directory -Force -Path "$TestDrive/ops/proj-a/.git" | Out-Null
        New-Item -ItemType Directory -Force -Path "$TestDrive/ops/not-a-repo" | Out-Null
        $repos = Get-DevRepos -Root $TestDrive
        $repos | Should -Contain $TestDrive
        ($repos | Where-Object { $_ -like "*proj-a" }) | Should -Not -BeNullOrEmpty
        ($repos | Where-Object { $_ -like "*not-a-repo" }) | Should -BeNullOrEmpty
    }
    It "discovers infra/ when it is itself a repo" {
        New-Item -ItemType Directory -Force -Path "$TestDrive/.git" | Out-Null
        New-Item -ItemType Directory -Force -Path "$TestDrive/infra/.git" | Out-Null
        $repos = Get-DevRepos -Root $TestDrive
        ($repos | Where-Object { $_ -like "*infra" }) | Should -Not -BeNullOrEmpty
    }
}
