BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $env:DOMOVOY_STORE = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("domovoy-test-" + [guid]::NewGuid().ToString('N'))
    $env:DOMOVOY_FEATURES_DIR = Join-Path -Path $repoRoot -ChildPath 'config/features'
    Import-Module (Join-Path -Path $repoRoot -ChildPath 'src/Domovoy/Domovoy.psd1') -Force
}

AfterAll {
    Remove-Module -Name Domovoy -ErrorAction SilentlyContinue
    if ($env:DOMOVOY_STORE -and (Test-Path -LiteralPath $env:DOMOVOY_STORE)) {
        Remove-Item -LiteralPath $env:DOMOVOY_STORE -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Module Domovoy' {

    It 'exports exactly 9 public commands' {
        @(Get-Command -Module Domovoy).Count | Should -Be 9
    }

    It 'parses every source file without syntax errors' {
        $bad = @()
        Get-ChildItem -LiteralPath (Join-Path -Path $repoRoot -ChildPath 'src') -Recurse -Filter '*.ps1' |
            ForEach-Object {
                $tokens = $null
                $errors = $null
                $null = [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors)
                if (@($errors).Count -gt 0) {
                    $bad += ("{0}: {1}" -f $_.Name, $errors[0].Message)
                }
            }
        $bad | Should -Be @()
    }

    It 'contains no network cmdlets in module source (invariant I4)' {
        $hits = Get-ChildItem -LiteralPath (Join-Path -Path $repoRoot -ChildPath 'src') -Recurse -Filter '*.ps1' |
            Select-String -Pattern 'Invoke-WebRequest|Invoke-RestMethod|WebClient|DownloadString|DownloadFile|Start-BitsTransfer'
        $hits | Should -Be @()
    }

    It 'Initialize-Domovoy creates the store and a genesis entry' {
        $init = Initialize-Domovoy
        Test-Path -LiteralPath $init.Ledger | Should -BeTrue
        Get-Content -LiteralPath $init.Ledger -Raw | Should -Match 'ledger.init'
    }

    It 'Initialize-Domovoy is idempotent' {
        $second = Initialize-Domovoy
        $second.GenesisCreated | Should -BeFalse
        @(Get-Content -LiteralPath $second.Ledger).Count | Should -Be 1
    }

    It 'Get-DomovoyFeature lists the reference manifests' {
        $features = @(Get-DomovoyFeature)
        $features.Count | Should -Be 2
        $features.Id | Should -Contain 'services.diagtrack.disabled'
        $features.Id | Should -Contain 'policy.telemetry.level0'
    }

    It 'Get-DomovoyFeature -Id filters to a single feature' {
        $one = @(Get-DomovoyFeature -Id 'policy.telemetry.level0')
        $one.Count | Should -Be 1
        $one[0].Category | Should -Be 'privacy'
    }

    It 'Invoke-DomovoyFeature dry-run returns a plan and changes nothing' {
        $plan = Invoke-DomovoyFeature -Id 'policy.telemetry.level0'
        $plan.Mode | Should -Be 'DryRun'
        @($plan.Plan).Count | Should -BeGreaterThan 0
        $plan.Plan[0].Op | Should -Be 'registry.set'
    }

    It 'Test-DomovoyEffect returns an honest probe matrix' {
        $result = Test-DomovoyEffect -Id 'policy.telemetry.level0'
        $result.Feature | Should -Be 'policy.telemetry.level0'
        @($result.Results).Count | Should -Be 1
        $result.Results[0].Probe | Should -Be 'registry.set'
        $result.Results[0].Expected | Should -Be '0'
    }

    It 'Get-DomovoyLedger returns the genesis event' {
        $entries = @(Get-DomovoyLedger -Event 'ledger.init')
        $entries.Count | Should -Be 1
    }
}
