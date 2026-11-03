# Domovoy v1.3.0 tests: feature groups with dependencies and an honest
# order report (catalog 102), the journal schema inventory and the explicit
# migration mechanism (catalog 101), and the read-only shell menu audit
# (catalog 104).
# Pester 5 evaluates -Skip at DISCOVERY, before any BeforeAll runs - the
# platform flag must live at the file top level, or every gate that reads
# it sees an undefined variable and the gate goes dead (v1.4.1, finding
# P1-13: the Windows-only blocks of these suites never executed in CI).
# NOTE: the variable must not be named *isWindows* - that name collides
# with the read-only automatic $IsWindows (names are case-insensitive).
$script:isWindowsPlatform = ($PSVersionTable.PSVersion.Major -lt 6) -or $IsWindows

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $env:DOMOVOY_STORE = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("domovoy-v13-" + [guid]::NewGuid().ToString('N'))
    $env:DOMOVOY_FEATURES_DIR = Join-Path -Path $repoRoot -ChildPath 'config/features'
    Import-Module (Join-Path -Path $repoRoot -ChildPath 'src/Domovoy/Domovoy.psd1') -Force

    $script:v13RepoRoot = $repoRoot
}

AfterAll {
    Remove-Module -Name Domovoy -Force -ErrorAction SilentlyContinue
    if ($env:DOMOVOY_STORE -like "$([System.IO.Path]::GetTempPath())domovoy-v13-*") {
        Remove-Item -LiteralPath $env:DOMOVOY_STORE -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Feature groups (catalog 102)' {

    BeforeEach {
        # A synthetic group directory per test; the real feature and profile
        # catalogs stay in place, so group resolution is exercised against
        # the shipped manifests.
        $script:groupsDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("domovoy-v13-groups-" + [guid]::NewGuid().ToString('N'))
        New-Item -Path $script:groupsDir -ItemType Directory -Force | Out-Null
        $env:DOMOVOY_GROUPS_DIR = $script:groupsDir
    }

    AfterEach {
        if ($script:groupsDir -and (Test-Path -LiteralPath $script:groupsDir)) {
            Remove-Item -LiteralPath $script:groupsDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        Remove-Item -Path env:DOMOVOY_GROUPS_DIR -ErrorAction SilentlyContinue
    }

    It 'lists the bundled groups' {
        Remove-Item -Path env:DOMOVOY_GROUPS_DIR -ErrorAction SilentlyContinue
        $groups = @(Get-DomovoyGroup)
        $groups.Count | Should -Be 2
        $groups.Id | Should -Contain 'privacy-essential'
        $groups.Id | Should -Contain 'home-essentials'
        $groups.MaxRisk | Should -Contain 'low'
        $groups.MaxRisk | Should -Contain 'medium'
        $groups[0].File | Should -Exist
    }

    It 'a group without any content source is an honest error' {
        @{ id = 'hollow'; title = 'Hollow'; maxRisk = 'low'; description = 'Declares nothing at all.' } |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path -Path $script:groupsDir -ChildPath 'hollow.json') -Encoding UTF8
        { Get-DomovoyGroup -Id hollow } | Should -Throw '*declares no dependsOn, profiles or features*'
    }

    It 'resolves dependencies before dependents and attributes every row' {
        @{ id = 'dep-base'; title = 'Base'; maxRisk = 'low'; description = 'The dependency group of this fixture.';
           features = @('policy.errorreporting.disabled') } |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path -Path $script:groupsDir -ChildPath 'dep-base.json') -Encoding UTF8
        @{ id = 'dep-root'; title = 'Root'; maxRisk = 'low'; description = 'Depends on the base group.';
           dependsOn = @('dep-base'); features = @('policy.activityhistory.disabled') } |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path -Path $script:groupsDir -ChildPath 'dep-root.json') -Encoding UTF8

        $plan = Invoke-DomovoyGroup -Id dep-root
        $plan.Mode | Should -Be 'DryRun'
        @($plan.Order).Count | Should -Be 2
        $plan.Order[0].Feature | Should -Be 'policy.errorreporting.disabled'
        $plan.Order[0].Group | Should -Be 'dep-base'
        $plan.Order[0].Source | Should -Be 'features'
        $plan.Order[0].Order | Should -Be 1
        $plan.Order[1].Feature | Should -Be 'policy.activityhistory.disabled'
        $plan.Order[1].Group | Should -Be 'dep-root'
        @($plan.Skipped).Count | Should -Be 0
    }

    It 'attributes profile features and reports duplicates with their first source' {
        @{ id = 'dup-base'; title = 'Base'; maxRisk = 'low'; description = 'Pulls the cautious profile.';
           profiles = @('cautious') } |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path -Path $script:groupsDir -ChildPath 'dup-base.json') -Encoding UTF8
        @{ id = 'dup-root'; title = 'Root'; maxRisk = 'low'; description = 'Pulls the same profile again plus one duplicate feature.';
           dependsOn = @('dup-base'); profiles = @('cautious'); features = @('services.diagtrack.disabled') } |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path -Path $script:groupsDir -ChildPath 'dup-root.json') -Encoding UTF8

        $plan = Invoke-DomovoyGroup -Id dup-root
        @($plan.Order).Count | Should -Be 15
        @($plan.Order | Where-Object { $_.Source -ne 'profile:cautious' }).Count | Should -Be 0
        # The whole second cautious pull plus the direct duplicate are
        # reported, not silently dropped.
        $duplicates = @($plan.Skipped | Where-Object { $_.Reason -like 'duplicate*' })
        $duplicates.Count | Should -Be 16
        $duplicates[0].Reason | Should -Be 'duplicate - already ordered via profile:cautious'
    }

    It 'skips features above the risk ceiling honestly' {
        @{ id = 'ceiling'; title = 'Ceiling'; maxRisk = 'low'; description = 'A low ceiling over a medium feature.';
           features = @('policy.telemetry.level0', 'policy.errorreporting.disabled') } |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path -Path $script:groupsDir -ChildPath 'ceiling.json') -Encoding UTF8

        $plan = Invoke-DomovoyGroup -Id ceiling
        @($plan.Order).Count | Should -Be 1
        $plan.Order[0].Feature | Should -Be 'policy.errorreporting.disabled'
        $plan.Skipped[0].Reason | Should -Be "risk 'medium' exceeds group max 'low'"
    }

    It 'skips missing profiles and missing manifests honestly' {
        @{ id = 'holes'; title = 'Holes'; maxRisk = 'low'; description = 'References things that do not exist.';
           profiles = @('no-such-profile'); features = @('no.such.feature') } |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path -Path $script:groupsDir -ChildPath 'holes.json') -Encoding UTF8

        $plan = Invoke-DomovoyGroup -Id holes
        @($plan.Order).Count | Should -Be 0
        @($plan.Skipped | Where-Object { $_.Reason -eq 'profile not found' }).Count | Should -Be 1
        @($plan.Skipped | Where-Object { $_.Reason -eq 'manifest not found' }).Count | Should -Be 1
    }

    It 'a dependency cycle names the whole chain' {
        @{ id = 'cyc-a'; title = 'A'; maxRisk = 'low'; description = 'Depends on B.';
           dependsOn = @('cyc-b'); features = @('policy.errorreporting.disabled') } |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path -Path $script:groupsDir -ChildPath 'cyc-a.json') -Encoding UTF8
        @{ id = 'cyc-b'; title = 'B'; maxRisk = 'low'; description = 'Depends on A - a cycle.';
           dependsOn = @('cyc-a'); features = @('policy.activityhistory.disabled') } |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path -Path $script:groupsDir -ChildPath 'cyc-b.json') -Encoding UTF8

        { Invoke-DomovoyGroup -Id cyc-a } | Should -Throw '*Group dependency cycle detected: cyc-a -> cyc-b -> cyc-a*'
    }

    It 'a self-dependency is a cycle of length one' {
        @{ id = 'cyc-self'; title = 'Self'; maxRisk = 'low'; description = 'Depends on itself.';
           dependsOn = @('cyc-self'); features = @('policy.errorreporting.disabled') } |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path -Path $script:groupsDir -ChildPath 'cyc-self.json') -Encoding UTF8

        { Invoke-DomovoyGroup -Id cyc-self } | Should -Throw '*Group dependency cycle detected: cyc-self -> cyc-self*'
    }

    It 'a missing dependency group names the requirer' {
        @{ id = 'orphan'; title = 'Orphan'; maxRisk = 'low'; description = 'Depends on nothing real.';
           dependsOn = @('no-such-group'); features = @('policy.errorreporting.disabled') } |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path -Path $script:groupsDir -ChildPath 'orphan.json') -Encoding UTF8

        { Invoke-DomovoyGroup -Id orphan } | Should -Throw "*Dependency group not found: 'no-such-group' (required by 'orphan')*"
    }

    It 'bundled home-essentials resolves the dependency first and dedups the overlap' {
        Remove-Item -Path env:DOMOVOY_GROUPS_DIR -ErrorAction SilentlyContinue
        $plan = Invoke-DomovoyGroup -Id home-essentials
        @($plan.Order).Count | Should -BeGreaterThan 0
        # Dependency content first: every dep-base row precedes every root row.
        $firstRootIdx = @($plan.Order | Where-Object { $_.Group -eq 'home-essentials' })[0].Order
        @($plan.Order | Where-Object { $_.Group -eq 'privacy-essential' -and $_.Order -gt $firstRootIdx }).Count | Should -Be 0
        # The cautious/standard overlap is reported as duplicates.
        @($plan.Skipped | Where-Object { $_.Reason -like 'duplicate*' }).Count | Should -BeGreaterThan 0
        # Direct features keep their honest attribution.
        @($plan.Order | Where-Object { $_.Feature -eq 'network.proxy.off' -and $_.Source -eq 'features' }).Count | Should -Be 1
    }

    It 'apply drives the pipeline and records one group.apply entry' -Skip:(-not $script:isWindowsPlatform) {
        @{ id = 'apply-g'; title = 'Apply'; maxRisk = 'low'; description = 'A real low-risk feature for apply.';
           features = @('policy.activityhistory.disabled') } |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path -Path $script:groupsDir -ChildPath 'apply-g.json') -Encoding UTF8

        $result = Invoke-DomovoyGroup -Id apply-g -Apply -SkipRestorePoint
        $result.Mode | Should -Be 'Apply'
        @($result.Applied).Count | Should -Be 1
        @($result.Skipped).Count | Should -Be 0

        $groupEvents = @(Get-DomovoyLedger -Event 'group.apply')
        $groupEvents.Count | Should -Be 1
        $groupEvents[0].groupId | Should -Be 'apply-g'
        $groupEvents[0].ordered | Should -Contain 'policy.activityhistory.disabled'
        @(Get-DomovoyLedger -Event 'feature.apply' -FeatureId 'policy.activityhistory.disabled').Count | Should -Be 1
        (Test-DomovoyLedgerIntegrity).ChainState | Should -Be 'ok'
    }

    It 'under -WhatIf nothing is applied and nothing is written' {
        # A fresh store: the shared store already carries the group.apply
        # entry of the apply test, and this assertion counts entries.
        $freshStore = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("domovoy-v13-whatif-" + [guid]::NewGuid().ToString('N'))
        $env:DOMOVOY_STORE = $freshStore
        New-Item -Path $freshStore -ItemType Directory -Force | Out-Null

        @{ id = 'whatif-g'; title = 'WhatIf'; maxRisk = 'low'; description = 'A real feature behind WhatIf.';
           features = @('policy.activityhistory.disabled') } |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path -Path $script:groupsDir -ChildPath 'whatif-g.json') -Encoding UTF8

        $null = Invoke-DomovoyGroup -Id whatif-g -Apply -SkipRestorePoint -WhatIf
        @(Get-DomovoyLedger -Event 'group.apply').Count | Should -Be 0
        @(Get-DomovoyLedger -Event 'feature.apply').Count | Should -Be 0

        Remove-Item -LiteralPath $freshStore -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Journal schema inventory and migration (catalog 101)' {

    BeforeEach {
        # A virgin store per test: the ledger assertions count lines.
        $script:v13Store = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("domovoy-v13-store-" + [guid]::NewGuid().ToString('N'))
        $env:DOMOVOY_STORE = $script:v13Store
        New-Item -Path $script:v13Store -ItemType Directory -Force | Out-Null
    }

    AfterAll {
        if ($script:v13Store -and (Test-Path -LiteralPath $script:v13Store)) {
            Remove-Item -LiteralPath $script:v13Store -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'a missing journal answers honestly' {
        $inventory = Get-DomovoyLedgerSchema
        $inventory.TotalEntries | Should -Be 0
        $inventory.Note | Should -BeLike '*does not exist*'
    }

    It 'a current-schema journal inventories cleanly' {
        InModuleScope Domovoy {
            $null = Write-DomovoyLedgerEntry -Entry @{ event = 'test.one'; featureId = 'schema.one' }
            $null = Write-DomovoyLedgerEntry -Entry @{ event = 'test.two'; featureId = 'schema.two' }
        }
        $inventory = Get-DomovoyLedgerSchema
        $inventory.TotalEntries | Should -Be 2
        $inventory.EntriesBelowCurrent | Should -Be 0
        $inventory.EntriesAboveCurrent | Should -Be 0
        $inventory.EntriesWithoutSchema | Should -Be 0
        $inventory.SchemaCounts.'schema-1' | Should -Be 2
        $inventory.HashedEntries | Should -Be 2
        $inventory.UnchainedEntries | Should -Be 0
    }

    It 'counts legacy, future and schema-less entries separately' {
        $ledger = Join-Path -Path $env:DOMOVOY_STORE -ChildPath 'ledger.jsonl'
        @(
            @{ timestamp = '2026-01-01T00:00:00.000Z'; event = 'ledger.init'; tool = 'Domovoy'; toolVersion = '0.5.0'; schema = 1 }
            @{ timestamp = '2026-01-02T00:00:00.000Z'; event = 'feature.apply'; featureId = 'future.entry'; schema = 2 }
            @{ timestamp = '2026-01-03T00:00:00.000Z'; event = 'feature.apply'; featureId = 'no.schema' }
        ) | ForEach-Object { $_ | ConvertTo-Json -Depth 8 -Compress } |
            Set-Content -LiteralPath $ledger -Encoding UTF8

        $inventory = Get-DomovoyLedgerSchema
        $inventory.TotalEntries | Should -Be 3
        $inventory.EntriesAboveCurrent | Should -Be 1
        $inventory.EntriesWithoutSchema | Should -Be 1
        $inventory.HighestSchema | Should -Be 2
        $inventory.SchemaCounts.'schema-2' | Should -Be 1
        $inventory.SchemaCounts.'schema-missing' | Should -Be 1
        $inventory.Note | Should -BeLike '*newer Domovoy*'
    }

    It 'an already-current journal: -Apply is an honest no-op that writes nothing' {
        InModuleScope Domovoy {
            $null = Write-DomovoyLedgerEntry -Entry @{ event = 'test.one'; featureId = 'schema.one' }
            $null = Write-DomovoyLedgerEntry -Entry @{ event = 'test.two'; featureId = 'schema.two' }
        }
        $result = Invoke-DomovoyLedgerMigration -Apply
        $result.Verdict | Should -Be 'already-current'
        $result.Applied | Should -BeFalse
        @(Get-Content -LiteralPath $result.Ledger).Count | Should -Be 2
        (Test-DomovoyLedgerIntegrity).ChainState | Should -Be 'ok'
    }

    It 'a newer journal is refused loudly on -Apply and never downgraded' {
        $ledger = Join-Path -Path $env:DOMOVOY_STORE -ChildPath 'ledger.jsonl'
        @{ timestamp = '2026-01-01T00:00:00.000Z'; event = 'feature.apply'; featureId = 'future.entry'; schema = 2 } |
            ConvertTo-Json -Depth 8 -Compress | Set-Content -LiteralPath $ledger -Encoding UTF8

        $plan = Invoke-DomovoyLedgerMigration
        $plan.Verdict | Should -Be 'future-entries'

        { Invoke-DomovoyLedgerMigration -Apply } | Should -Throw '*newer Domovoy*'
        # The refusal must not have touched the journal.
        (Get-Content -LiteralPath $ledger).Count | Should -Be 1
    }

    It 'a journal with older entries honestly says the rule is not defined yet' {
        $ledger = Join-Path -Path $env:DOMOVOY_STORE -ChildPath 'ledger.jsonl'
        # A hand-made entry carrying schema 0 - below the current 1.
        @{ timestamp = '2026-01-01T00:00:00.000Z'; event = 'ledger.init'; tool = 'Domovoy'; schema = 0 } |
            ConvertTo-Json -Depth 8 -Compress | Set-Content -LiteralPath $ledger -Encoding UTF8

        $plan = Invoke-DomovoyLedgerMigration
        $plan.Verdict | Should -Be 'migration-not-defined'
        $plan.Applied | Should -BeFalse
        $plan.Note | Should -BeLike '*no transformation*'
        (Get-Content -LiteralPath $ledger).Count | Should -Be 1
    }

    It 'the rewrite engine backs up, rebuilds the chain and keeps the journal verifiable' {
        # InModuleScope returns pipeline output; a $script: assignment inside
        # it lands in the module scope and is invisible out here.
        $rewrite = InModuleScope Domovoy {
            $null = Write-DomovoyLedgerEntry -Entry @{ event = 'test.one'; featureId = 'migrate.one' }
            $null = Write-DomovoyLedgerEntry -Entry @{ event = 'test.two'; featureId = 'migrate.two' }

            $ledgerPath = Get-DomovoyStorePath -SubPath 'ledger.jsonl'
            $originalLines = @(Get-Content -LiteralPath $ledgerPath)

            $rule = @{
                From      = 1
                To        = 2
                Transform = {
                    param($entry)
                    $null = $entry | Add-Member -NotePropertyName migratedBy -NotePropertyValue 'test-rule' -Force
                }
            }
            $result = Invoke-DomovoyLedgerRewrite -LedgerPath $ledgerPath -TargetSchema 2 -Transform $rule.Transform

            @{
                Result        = $result
                OriginalLines = $originalLines
                LedgerPath    = $ledgerPath
            }
        }

        $rewrite.Result.Migrated | Should -Be 2
        $rewrite.Result.Backup | Should -Exist
        # The backup keeps the original bytes and the original chain.
        @(Get-Content -LiteralPath $rewrite.Result.Backup).Count | Should -Be 2
        (Test-DomovoyLedgerIntegrity -Path $rewrite.Result.Backup).ChainState | Should -Be 'ok'

        # The rewritten journal: schema 2 everywhere, chain rebuilt.
        $lines = @(Get-Content -LiteralPath $rewrite.LedgerPath)
        $lines.Count | Should -Be 2
        $first = $lines[0] | ConvertFrom-Json
        $second = $lines[1] | ConvertFrom-Json
        $first.schema | Should -Be 2
        $second.schema | Should -Be 2
        $first.migratedBy | Should -Be 'test-rule'
        $first.prevHash | Should -Be 'genesis'
        $second.prevHash | Should -Be $first.hash
        $integrity = Test-DomovoyLedgerIntegrity -Path $rewrite.Result.LedgerPath
        $integrity.ChainState | Should -Be 'ok'
        $integrity.HashedEntries | Should -Be 2
    }

    It 'the audit entry chains onto the migrated tail and is filterable' {
        InModuleScope Domovoy {
            $null = Write-DomovoyLedgerEntry -Entry @{ event = 'test.one'; featureId = 'migrate.one' }

            $ledgerPath = Get-DomovoyStorePath -SubPath 'ledger.jsonl'
            $rule = @{
                From      = 1
                To        = 2
                Transform = { param($entry) }
            }
            $null = Invoke-DomovoyLedgerRewrite -LedgerPath $ledgerPath -TargetSchema 2 -Transform $rule.Transform

            $null = Write-DomovoyLedgerEntry -Entry @{
                event         = 'ledger.migrate'
                fromSchema    = 1
                toSchema      = 2
                migratedCount = 1
            }
        }
        $events = @(Get-DomovoyLedger -Event 'ledger.migrate')
        $events.Count | Should -Be 1
        $events[0].toSchema | Should -Be 2
        (Test-DomovoyLedgerIntegrity).ChainState | Should -Be 'ok'
    }

    It 'a torn line stops the rewrite before any byte changes' {
        InModuleScope Domovoy {
            $null = Write-DomovoyLedgerEntry -Entry @{ event = 'test.one'; featureId = 'torn.one' }
            $ledgerPath = Get-DomovoyStorePath -SubPath 'ledger.jsonl'
            Add-Content -LiteralPath $ledgerPath -Value '{ this is not json' -Encoding UTF8

            $before = Get-Content -LiteralPath $ledgerPath -Raw
            $rule = @{ From = 1; To = 2; Transform = { param($entry) } }
            { Invoke-DomovoyLedgerRewrite -LedgerPath $ledgerPath -TargetSchema 2 -Transform $rule.Transform } |
                Should -Throw '*line 2*'
            # Nothing changed: same bytes, no backup files appeared.
            (Get-Content -LiteralPath $ledgerPath -Raw) | Should -Be $before
            @(Get-ChildItem -LiteralPath (Split-Path -Parent $ledgerPath) -Filter 'ledger.backup-*').Count | Should -Be 0
        }
    }
}

Describe 'Shell menu audit (catalog 104)' -Skip:(-not $script:isWindowsPlatform) {

    BeforeAll {
        # Synthetic, fully documented registrations under HKCU: the merged
        # HKCR view and the per-user FileExts key pick them up.
        $script:v13Temp = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("domovoy-v13-shell-" + [guid]::NewGuid().ToString('N'))
        New-Item -Path $script:v13Temp -ItemType Directory -Force | Out-Null
        $script:v13Dll = Join-Path -Path $script:v13Temp -ChildPath 'domovoy-test.dll'
        Set-Content -LiteralPath $script:v13Dll -Value 'placeholder' -Encoding ASCII

        $script:v13ClsidOk = '{' + [guid]::NewGuid().ToString().ToUpperInvariant() + '}'
        $script:v13ClsidMissing = '{' + [guid]::NewGuid().ToString().ToUpperInvariant() + '}'

        $classesClsid = 'Registry::HKEY_CURRENT_USER\Software\Classes\CLSID'
        $null = New-Item -Path (Join-Path -Path $classesClsid -ChildPath $script:v13ClsidOk) -Force
        $null = New-Item -Path (Join-Path -Path $classesClsid -ChildPath "$($script:v13ClsidOk)\InprocServer32") -Force
        $null = Set-Item -LiteralPath (Join-Path -Path $classesClsid -ChildPath "$($script:v13ClsidOk)\InprocServer32") -Value $script:v13Dll

        $null = New-Item -Path (Join-Path -Path $classesClsid -ChildPath $script:v13ClsidMissing) -Force
        $null = New-Item -Path (Join-Path -Path $classesClsid -ChildPath "$($script:v13ClsidMissing)\InprocServer32") -Force
        $null = Set-Item -LiteralPath (Join-Path -Path $classesClsid -ChildPath "$($script:v13ClsidMissing)\InprocServer32") -Value 'C:\nonexistent\domovoy-missing.dll'

        $handlerBase = 'Registry::HKEY_CURRENT_USER\Software\Classes\Directory\shellex\ContextMenuHandlers'
        $null = New-Item -Path (Join-Path -Path $handlerBase -ChildPath 'DomovoyTestOk') -Force
        $null = Set-Item -LiteralPath (Join-Path -Path $handlerBase -ChildPath 'DomovoyTestOk') -Value $script:v13ClsidOk
        $null = New-Item -Path (Join-Path -Path $handlerBase -ChildPath 'DomovoyTestMissing') -Force
        $null = Set-Item -LiteralPath (Join-Path -Path $handlerBase -ChildPath 'DomovoyTestMissing') -Value $script:v13ClsidMissing

        $extKey = 'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.domotest'
        $null = New-Item -Path (Join-Path -Path $extKey -ChildPath 'OpenWithList') -Force
        $null = New-ItemProperty -LiteralPath (Join-Path -Path $extKey -ChildPath 'OpenWithList') -Name 'a' -Value 'domotest.exe' -PropertyType String -Force
        $null = New-ItemProperty -LiteralPath (Join-Path -Path $extKey -ChildPath 'OpenWithList') -Name 'MRUList' -Value 'a' -PropertyType String -Force
        $null = New-Item -Path (Join-Path -Path $extKey -ChildPath 'OpenWithProgids') -Force
        $null = New-ItemProperty -LiteralPath (Join-Path -Path $extKey -ChildPath 'OpenWithProgids') -Name 'domotest.progid' -Value '' -PropertyType String -Force
    }

    AfterAll {
        Remove-Item -LiteralPath (Join-Path -Path 'Registry::HKEY_CURRENT_USER\Software\Classes\Directory\shellex\ContextMenuHandlers' -ChildPath 'DomovoyTestOk') -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath (Join-Path -Path 'Registry::HKEY_CURRENT_USER\Software\Classes\Directory\shellex\ContextMenuHandlers' -ChildPath 'DomovoyTestMissing') -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath (Join-Path -Path 'Registry::HKEY_CURRENT_USER\Software\Classes\CLSID' -ChildPath $script:v13ClsidOk) -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath (Join-Path -Path 'Registry::HKEY_CURRENT_USER\Software\Classes\CLSID' -ChildPath $script:v13ClsidMissing) -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath 'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.domotest' -Recurse -Force -ErrorAction SilentlyContinue
        if ($script:v13Temp -and (Test-Path -LiteralPath $script:v13Temp)) {
            Remove-Item -LiteralPath $script:v13Temp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'finds the synthetic handler with the DLL present' {
        $report = Get-DomovoyShellMenuReport
        $report.LocationsScanned | Should -Be 6
        $row = @($report.ContextMenuHandlers | Where-Object { $_.Clsid -eq $script:v13ClsidOk })
        $row.Count | Should -Be 1
        $row[0].Location | Should -Be 'Directory'
        $row[0].Handler | Should -Be 'DomovoyTestOk'
        $row[0].Server | Should -Be $script:v13Dll
        $row[0].DllPresent | Should -BeTrue
    }

    It 'reports a handler whose DLL is gone as dll-missing' {
        $report = Get-DomovoyShellMenuReport
        $row = @($report.ContextMenuHandlers | Where-Object { $_.Clsid -eq $script:v13ClsidMissing })
        $row.Count | Should -Be 1
        $row[0].DllPresent | Should -BeFalse
        $report.Summary.HandlersMissingDll | Should -BeGreaterOrEqual 1
    }

    It 'inventories the Open-with choices for the synthetic extension' {
        $report = Get-DomovoyShellMenuReport
        $row = @($report.OpenWithExtensions | Where-Object { $_.Extension -eq '.domotest' })
        $row.Count | Should -Be 1
        $row[0].Programs | Should -Contain 'domotest.exe'
        $row[0].ProgIds | Should -Contain 'domotest.progid'
        $row[0].Mrulist | Should -Be 'a'
        $row[0].Choices | Should -Be 2
        $report.OpenWithExtensionsScanned | Should -BeGreaterOrEqual 1
    }

    It 'the -Extension filter narrows the Open-with section to one row' {
        $report = Get-DomovoyShellMenuReport -Extension domotest
        @($report.OpenWithExtensions).Count | Should -Be 1
        $report.OpenWithExtensions[0].Extension | Should -Be '.domotest'
    }
}
