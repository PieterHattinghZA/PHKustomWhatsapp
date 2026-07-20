<#
.SYNOPSIS
Pester validation for PHKustomWhatsapp.
#>

BeforeAll {
    $script:RepositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:ManifestPath = Join-Path $script:RepositoryRoot 'PHKustomWhatsapp.psd1'
}

Describe 'Module packaging' {
    It 'has a valid version 4.0.0 manifest' {
        $manifest = Test-ModuleManifest -Path $script:ManifestPath -ErrorAction Stop
        $manifest.Version.ToString() | Should -Be '4.0.0'
    }

    It 'declares Windows PowerShell 5.1 compatibility' {
        $data = Import-PowerShellDataFile -Path $script:ManifestPath
        $data.PowerShellVersion | Should -Be '5.1'
    }

    It 'has no undeclared external module dependency' {
        $data = Import-PowerShellDataFile -Path $script:ManifestPath
        @($data.RequiredModules).Count | Should -Be 0
    }

    It 'contains every private implementation file' {
        Test-Path (Join-Path $script:RepositoryRoot 'Private\Configuration.ps1') | Should -BeTrue
        Test-Path (Join-Path $script:RepositoryRoot 'Private\ApiClient.ps1') | Should -BeTrue
    }
}

Describe 'PowerShell syntax' {
    $files = Get-ChildItem -Path $script:RepositoryRoot -Recurse -File |
        Where-Object { $_.Extension -in @('.ps1','.psm1','.psd1') }

    foreach ($file in $files) {
        It "parses $($file.FullName) without syntax errors" {
            $tokens = $null
            $errors = $null
            [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors) | Out-Null
            @($errors).Count | Should -Be 0
        }
    }
}

Describe 'Security regression checks' {
    It 'does not contain the previously published instance or telephone identifiers' {
        $source = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot 'PHKustomWhatsapp.psm1') -Raw
        $source | Should -Not -Match '7103300833'
        $source | Should -Not -Match '27645258757'
    }

    It 'uses a protected token field for new configuration' {
        $source = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot 'Private\Configuration.ps1') -Raw
        $source | Should -Match 'apiTokenProtected'
        $source | Should -Match 'ConvertFrom-SecureString'
        $source | Should -Match 'SetAccessRuleProtection'
    }

    It 'does not silently swallow exceptions in production scripts' {
        $productionFiles = @(
            (Join-Path $script:RepositoryRoot 'PHKustomWhatsapp.psm1'),
            (Join-Path $script:RepositoryRoot 'simple-gui.ps1'),
            (Join-Path $script:RepositoryRoot 'Private\Configuration.ps1'),
            (Join-Path $script:RepositoryRoot 'Private\ApiClient.ps1')
        )
        foreach ($path in $productionFiles) {
            (Get-Content -LiteralPath $path -Raw) | Should -Not -Match 'catch\s*\{\s*\}'
        }
    }
}

Describe 'API query encoding' {
    BeforeAll {
        . (Join-Path $script:RepositoryRoot 'Private\ApiClient.ps1')
    }

    It 'URL-encodes query names and values' {
        $query = ConvertTo-WhatsappQueryString -QueryParams @{ 'message id' = 'A&B+C' }
        $query | Should -Be 'message%20id=A%26B%2BC'
    }
}
