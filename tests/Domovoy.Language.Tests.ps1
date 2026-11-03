# Localization tests (v1.6 item 6): the strings table, the language switch
# and the honest resolution order. ASCII-only on purpose - the RU wording is
# never pinned here (the parity test compares key sets, not literals), so
# this file needs no BOM and runs on every platform.

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $env:DOMOVOY_STORE = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("domovoy-lang-" + [guid]::NewGuid().ToString('N'))
    $env:DOMOVOY_FEATURES_DIR = Join-Path -Path $repoRoot -ChildPath 'config/features'
    Import-Module (Join-Path -Path $repoRoot -ChildPath 'src/Domovoy/Domovoy.psd1') -Force
}

AfterAll {
    Remove-Module -Name Domovoy -Force -ErrorAction SilentlyContinue
    if ($env:DOMOVOY_STORE -like "$([System.IO.Path]::GetTempPath())domovoy-lang-*") {
        Remove-Item -LiteralPath $env:DOMOVOY_STORE -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Strings table (v1.6 item 6)' {
    It 'returns the EN table on the default branch without throwing (regression: runs 54-55)' {
        # Runs 54/55: with a fresh store and no session override the table
        # lookup received a $null language and threw at ContainsKey - the
        # GUI-preview and change-report tests of OTHER suites hit exactly
        # this branch while the language suite always set a language first.
        $table = InModuleScope Domovoy { Get-DomovoyStrings }
        $table.windowTitle | Should -Not -BeNullOrEmpty
        $table.reportEventDefault | Should -Be 'event'
    }
    It 'resolves to en by default with a fresh store' {
        $status = Get-DomovoyLanguage
        $status.Language | Should -Be 'en'
        $status.Source | Should -Be 'default'
    }

    It 'carries the same key set for every language - parity is machine-checked, not promised' {
        InModuleScope Domovoy {
            # Reach both tables through the module internals: the private
            # resolver returns one language at a time, so the tables are
            # extracted by overriding the session language per call.
            $keys = @{}
            foreach ($lang in @('en', 'ru')) {
                $script:DomovoyLanguage = $lang
                $table = Get-DomovoyStrings
                $keys[$lang] = @($table.Keys | Sort-Object)
            }
            $script:DomovoyLanguage = $null
            $keys['en'].Count | Should -BeGreaterThan 20
            $keys['en'] | Should -Be $keys['ru']
        }
    }

    It 'switches the session language and persists the preference file' {
        $result = Set-DomovoyLanguage -Language ru
        $result.Previous | Should -Be 'en'
        $result.Language | Should -Be 'ru'
        $result.Persisted | Should -BeTrue
        Test-Path -LiteralPath $result.PreferenceFile | Should -BeTrue

        $status = Get-DomovoyLanguage
        $status.Language | Should -Be 'ru'
        # The session override wins, so the source is the session even
        # though the file was just written.
        $status.Source | Should -Be 'session'

        # A fresh module session (no session variable) reads the store.
        InModuleScope Domovoy { $script:DomovoyLanguage = $null }
        $status2 = Get-DomovoyLanguage
        $status2.Language | Should -Be 'ru'
        $status2.Source | Should -Be 'store'
    }

    It 'falls back to en on an unknown stored language' {
        Set-DomovoyLanguage -Language ru | Out-Null
        InModuleScope Domovoy { $script:DomovoyLanguage = $null }
        Set-Content -LiteralPath (Join-Path -Path $env:DOMOVOY_STORE -ChildPath 'language.txt') -Value 'de' -Encoding UTF8
        $status = Get-DomovoyLanguage
        $status.Language | Should -Be 'en'
        $status.Source | Should -Be 'default'
    }

    It 'the strings file carries a UTF-8 BOM so PS 5.1 reads the Cyrillic table honestly' {
        $path = Join-Path -Path $repoRoot -ChildPath 'src/Domovoy/Private/Get-DomovoyStrings.ps1'
        $head = [System.IO.File]::ReadAllBytes($path)[0..2]
        ($head[0] -eq 0xEF -and $head[1] -eq 0xBB -and $head[2] -eq 0xBF) | Should -BeTrue
    }
}

Describe 'Change report speaks the active language (v1.6 item 6)' {
    It 'the human summary switches with the language while event names stay frozen' {
        InModuleScope Domovoy {
            $entry = Write-DomovoyLedgerEntry -Entry @{ event = 'feature.undo'; featureId = 'lang.fixture' }
            # The report is one object; the human rows live in .Report.
            $en = (Get-DomovoyChangeReport -Last 10).Report | Where-Object { $_.FeatureId -eq 'lang.fixture' } | Select-Object -Last 1 -ExpandProperty Summary
            Set-DomovoyLanguage -Language ru | Out-Null
            $ru = (Get-DomovoyChangeReport -Last 10).Report | Where-Object { $_.FeatureId -eq 'lang.fixture' } | Select-Object -Last 1 -ExpandProperty Summary
            Set-DomovoyLanguage -Language en | Out-Null
            $back = (Get-DomovoyChangeReport -Last 10).Report | Where-Object { $_.FeatureId -eq 'lang.fixture' } | Select-Object -Last 1 -ExpandProperty Summary

            $en | Should -Not -Be $ru
            $back | Should -Be $en
            $en | Should -Not -BeNullOrEmpty
            $ru | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Language commands are first-class public commands (v1.6 item 6)' {
    It 'both are exported with a validate-set guarded parameter' {
        $get = Get-Command Get-DomovoyLanguage
        $set = Get-Command Set-DomovoyLanguage
        $get | Should -Not -BeNullOrEmpty
        $set | Should -Not -BeNullOrEmpty
        $set.Parameters['Language'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] } |
            Select-Object -First 1 -ExpandProperty ValidValues | Should -Be @('en', 'ru')
    }
}
