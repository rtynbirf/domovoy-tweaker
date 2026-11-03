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

    It 'exports exactly the commands the manifest declares (54 at v1.5.0)' {
        # The count follows the manifest, not a frozen literal: the literal
        # rots on every catalog-localized wave (the 52->54 language pair of
        # v1.5.0 was exactly that rot), while the CI documentation-freshness
        # gate already pins the README claim to the same manifest number.
        $manifest = Import-PowerShellDataFile -Path (Join-Path -Path $repoRoot -ChildPath 'src/Domovoy/Domovoy.psd1')
        @(Get-Command -Module Domovoy).Count | Should -Be @($manifest.FunctionsToExport).Count
        @(Get-Command -Module Domovoy).Count | Should -BeGreaterThan 50
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

    It 'genesis ledger entry records the module version' {
        $first = (Get-Content -LiteralPath (Initialize-Domovoy).Ledger -TotalCount 1) | ConvertFrom-Json
        $first.toolVersion | Should -Be ((Get-Module -Name Domovoy).Version.ToString())
    }

    It 'Initialize-Domovoy is idempotent' {
        $second = Initialize-Domovoy
        $second.GenesisCreated | Should -BeFalse
        @(Get-Content -LiteralPath $second.Ledger).Count | Should -Be 1
    }

    It 'Get-DomovoyFeature lists the reference manifests' {
        $features = @(Get-DomovoyFeature)
        $features.Count | Should -Be 58
        $features.Id | Should -Contain 'services.diagtrack.disabled'
        $features.Id | Should -Contain 'policy.telemetry.level0'
        $features.Id | Should -Contain 'services.dmwappush.disabled'
        $features.Id | Should -Contain 'services.remoteregistry.disabled'
        $features.Id | Should -Contain 'policy.feedback.notifications.hidden'
        $features.Id | Should -Contain 'privacy.advertisinginfo.disabled'
        $features.Id | Should -Contain 'privacy.tailoredexperiences.disabled'
        $features.Id | Should -Contain 'privacy.consumerfeatures.disabled'
        $features.Id | Should -Contain 'privacy.cortana.disabled'
        $features.Id | Should -Contain 'privacy.onedrive.filesync.disabled'
        $features.Id | Should -Contain 'packages.onedrive.store.removed'
        $features.Id | Should -Contain 'packages.chat.removed'
        $features.Id | Should -Contain 'packages.xboxgamingoverlay.removed'
        $features.Id | Should -Contain 'packages.cortana.app.removed'
        $features.Id | Should -Contain 'packages.gethelp.removed'
        $features.Id | Should -Contain 'packages.getstarted.removed'
        $features.Id | Should -Contain 'ui.contextmenu.classic'
        $features.Id | Should -Contain 'ui.explorer.advanced.visibility'
        $features.Id | Should -Contain 'ui.widgets.panel.disabled'
        $features.Id | Should -Contain 'policy.input.personalization.disabled'
        $features.Id | Should -Contain 'policy.search.cloudsearch.disabled'
        $features.Id | Should -Contain 'scheduler.telemetry-tasks.disabled'
        $features.Id | Should -Contain 'policy.diagnostics.sending.blocked'
        $features.Id | Should -Contain 'policy.edge.background.disabled'
        $features.Id | Should -Contain 'ui.taskbar.cleanup'
        $features.Id | Should -Contain 'policy.windows-tips.disabled'
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

    It 'Get-DomovoyProfile lists both bundled profiles' {
        $profiles = @(Get-DomovoyProfile)
        $profiles.Count | Should -Be 2
        $profiles.Id | Should -Contain 'cautious'
        $profiles.Id | Should -Contain 'standard'
        $profiles.MaxRisk | Should -Contain 'low'
        $profiles.MaxRisk | Should -Contain 'medium'
    }

    It 'Backup-DomovoyServiceState writes a readable service table snapshot' {
        $backup = Backup-DomovoyServiceState
        Test-Path -LiteralPath $backup.File | Should -BeTrue
        $backup.Services | Should -BeGreaterThan 0
        $parsed = Get-Content -LiteralPath $backup.File -Raw -Encoding UTF8 | ConvertFrom-Json
        $parsed.count | Should -Be $backup.Services
        @($parsed.services).Count | Should -Be $backup.Services
    }
}
