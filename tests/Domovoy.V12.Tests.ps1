# Domovoy v1.2.0 tests: the ledger hash chain with its honest verifier
# (catalog 103), the file.timestamp op with all four projections (catalog 91),
# the documented catalog wave (80/82/86/74), the driver rollback-readiness
# report (catalog 90) and the component store cleanup trigger (catalog 88).
# Pester 5 evaluates -Skip at DISCOVERY, before any BeforeAll runs - the
# platform flag must live at the file top level, or every gate that reads
# it sees an undefined variable and the gate goes dead (v1.4.1, finding
# P1-13: the Windows-only blocks of these suites never executed in CI).
# NOTE: the variable must not be named *isWindows* - that name collides
# with the read-only automatic $IsWindows (names are case-insensitive).
$script:isWindowsPlatform = ($PSVersionTable.PSVersion.Major -lt 6) -or $IsWindows

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $env:DOMOVOY_STORE = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("domovoy-v12-" + [guid]::NewGuid().ToString('N'))
    $env:DOMOVOY_FEATURES_DIR = Join-Path -Path $repoRoot -ChildPath 'config/features'
    Import-Module (Join-Path -Path $repoRoot -ChildPath 'src/Domovoy/Domovoy.psd1') -Force

    $script:v12SchemaPath = Join-Path -Path $repoRoot -ChildPath 'schema/features.schema.json'
}

AfterAll {
    Remove-Module -Name Domovoy -Force -ErrorAction SilentlyContinue
    if ($env:DOMOVOY_STORE -like "$([System.IO.Path]::GetTempPath())domovoy-v12-*") {
        Remove-Item -LiteralPath $env:DOMOVOY_STORE -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Ledger hash chain (catalog 103)' {
    BeforeEach {
        # A virgin store per test: the chain assertions count lines.
        $script:v12Store = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("domovoy-v12-chain-" + [guid]::NewGuid().ToString('N'))
        $env:DOMOVOY_STORE = $script:v12Store
        # The legacy-journal tests write the ledger file directly, so the
        # store directory must exist before the first Set-Content.
        New-Item -Path $script:v12Store -ItemType Directory -Force | Out-Null
    }

    AfterAll {
        if ($script:v12Store -and (Test-Path -LiteralPath $script:v12Store)) {
            Remove-Item -LiteralPath $script:v12Store -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'binds every new entry to its predecessor by hash' {
        InModuleScope Domovoy {
            $null = Write-DomovoyLedgerEntry -Entry @{ event = 'test.first';  featureId = 'chain.one' }
            $null = Write-DomovoyLedgerEntry -Entry @{ event = 'test.second'; featureId = 'chain.two' }
        }
        $ledger = Join-Path -Path $env:DOMOVOY_STORE -ChildPath 'ledger.jsonl'
        $lines = @(Get-Content -LiteralPath $ledger)
        $lines.Count | Should -Be 2
        $first = $lines[0] | ConvertFrom-Json
        $second = $lines[1] | ConvertFrom-Json
        $first.hash | Should -Match '^[0-9a-f]{64}$'
        $second.hash | Should -Match '^[0-9a-f]{64}$'
        $first.prevHash | Should -Be 'genesis'
        $second.prevHash | Should -Be $first.hash

        $integrity = Test-DomovoyLedgerIntegrity
        $integrity.ChainState | Should -Be 'ok'
        $integrity.HashedEntries | Should -Be 2
        $integrity.HashMismatches | Should -Be 0
    }

    It 'an edited entry breaks the chain at its exact line' {
        InModuleScope Domovoy {
            $null = Write-DomovoyLedgerEntry -Entry @{ event = 'test.first';  featureId = 'chain.one' }
            $null = Write-DomovoyLedgerEntry -Entry @{ event = 'test.second'; featureId = 'chain.two' }
        }
        $ledger = Join-Path -Path $env:DOMOVOY_STORE -ChildPath 'ledger.jsonl'
        # Rewrite history: flip the recorded feature id of the first entry.
        $lines = @(Get-Content -LiteralPath $ledger)
        $lines[0] = $lines[0] -replace 'chain\.one', 'chain.REWRITTEN'
        Set-Content -LiteralPath $ledger -Value $lines -Encoding UTF8

        $integrity = Test-DomovoyLedgerIntegrity
        $integrity.ChainState | Should -Be 'broken'
        $integrity.HashMismatches | Should -Be 1
        $integrity.FirstBrokenLine | Should -Be 1

        $detail = Test-DomovoyLedgerIntegrity -Detail
        $detail.Detail[0].Verdict | Should -Be 'hash-mismatch'
        $detail.Detail[0].RecomputedHash | Should -Not -Be $detail.Detail[0].StoredHash
    }

    It 'a reordered entry is caught through the predecessor binding' {
        InModuleScope Domovoy {
            $null = Write-DomovoyLedgerEntry -Entry @{ event = 'test.first';  featureId = 'chain.one' }
            $null = Write-DomovoyLedgerEntry -Entry @{ event = 'test.second'; featureId = 'chain.two' }
        }
        $ledger = Join-Path -Path $env:DOMOVOY_STORE -ChildPath 'ledger.jsonl'
        $lines = @(Get-Content -LiteralPath $ledger)
        # The hashes still verify (the canonical form did not change), but the
        # predecessor binding no longer does.
        Set-Content -LiteralPath $ledger -Value @($lines[1], $lines[0]) -Encoding UTF8

        $integrity = Test-DomovoyLedgerIntegrity
        $integrity.ChainState | Should -Be 'broken'
        $integrity.PrevHashMismatches | Should -BeGreaterOrEqual 1
    }

    It 'a legacy journal answers honestly: no chain, not a failure' {
        $ledger = Join-Path -Path $env:DOMOVOY_STORE -ChildPath 'ledger.jsonl'
        @(
            @{ timestamp = '2026-01-01T00:00:00.000Z'; event = 'ledger.init'; tool = 'Domovoy'; toolVersion = '0.5.0'; schema = 1 }
            @{ timestamp = '2026-01-02T00:00:00.000Z'; event = 'feature.apply'; featureId = 'old.feature'; tool = 'Domovoy'; toolVersion = '0.5.0'; schema = 1; snapshot = @(); verification = @{ AllPass = $true; Results = @() } }
        ) | ForEach-Object { $_ | ConvertTo-Json -Depth 8 -Compress } |
            Set-Content -LiteralPath $ledger -Encoding UTF8

        $integrity = Test-DomovoyLedgerIntegrity
        $integrity.ChainState | Should -Be 'absent'
        $integrity.UnchainedEntries | Should -Be 2
        $integrity.Note | Should -BeLike '*predate v1.2*'
    }

    It 'a mixed journal verifies the hashed tail and counts the head' {
        $ledger = Join-Path -Path $env:DOMOVOY_STORE -ChildPath 'ledger.jsonl'
        @{ timestamp = '2026-01-01T00:00:00.000Z'; event = 'ledger.init'; tool = 'Domovoy'; toolVersion = '0.5.0'; schema = 1 } |
            ConvertTo-Json -Depth 8 -Compress |
            Set-Content -LiteralPath $ledger -Encoding UTF8

        InModuleScope Domovoy {
            $null = Write-DomovoyLedgerEntry -Entry @{ event = 'feature.apply'; featureId = 'new.feature'; snapshot = @(); verification = @{ AllPass = $true; Results = @() } }
        }

        $integrity = Test-DomovoyLedgerIntegrity
        $integrity.ChainState | Should -Be 'ok'
        $integrity.UnchainedEntries | Should -Be 1
        $integrity.HashedEntries | Should -Be 1
        # The first hashed entry of a legacy journal binds to genesis - the
        # documented writer rule.
        $detailed = Test-DomovoyLedgerIntegrity -Detail
        $detailed.Detail[1].StoredPrevHash | Should -Be 'genesis'
    }

    It 'the canonical serializer is deterministic and key-order independent' {
        $left = InModuleScope Domovoy { Get-DomovoyCanonicalJson -Value @{ b = 1; a = 'x'; nested = @{ y = @(2, 1); x = $true } } }
        $right = InModuleScope Domovoy { Get-DomovoyCanonicalJson -Value @{ a = 'x'; nested = @{ x = $true; y = @(2, 1) }; b = 1 } }
        $left | Should -Be $right
        $left | Should -BeLike '{*'
        $left | Should -BeLike '*"a":"x"*'
        $left | Should -BeLike '*"x":true*'
        # The object canonical form is brace-wrapped, the array order kept.
        $arrayForm = InModuleScope Domovoy { Get-DomovoyCanonicalJson -Value @('b', 'a') }
        $arrayForm | Should -Be '["b","a"]'
    }
}

Describe 'file.timestamp op (catalog 91)' {
    BeforeAll {
        $script:v12ManifestDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("domovoy-v12-manifests-" + [guid]::NewGuid().ToString('N'))
        New-Item -Path $script:v12ManifestDir -ItemType Directory -Force | Out-Null
        InModuleScope Domovoy { Mock Test-DomovoyAdmin { return $true } }
    }

    AfterAll {
        Remove-Item -LiteralPath $script:v12ManifestDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'the fixture manifest validates against the schema (op and probe)' {
        $manifest = Join-Path -Path $script:v12ManifestDir -ChildPath 'v12.stamp.json'
        @{
            id = 'v12.stamp'
            title = 'V12 fixture: pin file timestamps'
            version = '1.2.0'
            category = 'maintenance'
            risk = 'low'
            description = 'Test fixture: pins creation and last-write stamps of a scratch file.'
            ops = @(
                @{ type = 'file.timestamp'; path = 'C:\Windows\Temp\domovoy-v12-nonexistent.txt'; creation = '2024-01-15T10:30:00Z'; lastWrite = '2024-01-15T10:30:00Z'; allowMissing = $false }
            )
            undo = @{ mode = 'snapshot' }
            verify = @(
                @{ type = 'file.timestamp'; path = 'C:\Windows\Temp\domovoy-v12-nonexistent.txt'; creation = '2024-01-15T10:30:00Z'; lastWrite = '2024-01-15T10:30:00Z' }
            )
            references = @('https://learn.microsoft.com/windows/win32/sysinfo/registry')
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifest -Encoding UTF8

        { Test-Json -Json (Get-Content -LiteralPath $manifest -Raw) -SchemaFile $script:v12SchemaPath } | Should -Not -Throw
    }

    It 'dry-run plans the stamps and says <keep> for unpinned fields' -Skip:(-not $script:isWindowsPlatform) {
        $scratch = Join-Path -Path $env:TEMP -ChildPath ("domovoy-v12-ts-" + [guid]::NewGuid().ToString('N') + '.txt')
        Set-Content -LiteralPath $scratch -Value 'domovoy' -Encoding UTF8

        $manifest = Join-Path -Path $script:v12ManifestDir -ChildPath 'v12.stamp.dry.json'
        @{
            id = 'v12.stamp.dry'
            title = 'V12 fixture: dry-run stamp plan'
            version = '1.2.0'
            category = 'maintenance'
            risk = 'low'
            description = 'Test fixture: plans creation and last-write stamps, keeps access.'
            ops = @( @{ type = 'file.timestamp'; path = $scratch; creation = '2024-01-15T10:30:00Z'; lastWrite = '2024-01-15T10:30:00Z' } )
            undo = @{ mode = 'snapshot' }
            verify = @( @{ type = 'file.timestamp'; path = $scratch; creation = '2024-01-15T10:30:00Z'; lastWrite = '2024-01-15T10:30:00Z' } )
            references = @('https://learn.microsoft.com/windows/win32/sysinfo/registry')
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifest -Encoding UTF8

        $dry = Invoke-DomovoyFeature -ManifestFile $manifest
        $dry.Mode | Should -Be 'DryRun'
        $dry.Plan[0].Op | Should -Be 'file.timestamp'
        $dry.Plan[0].Target | Should -Be $scratch
        $dry.Plan[0].Current | Should -BeLike 'creation=2*'
        $dry.Plan[0].New | Should -BeLike 'creation=2024-01-15T10:30:00Z;lastWrite=2024-01-15T10:30:00Z;lastAccess=<keep>'

        Remove-Item -LiteralPath $scratch -Force -ErrorAction SilentlyContinue
    }

    It 'apply sets the stamps, the probe compares instants, undo restores exactly' -Skip:(-not $script:isWindowsPlatform) {
        $scratch = Join-Path -Path $env:TEMP -ChildPath ("domovoy-v12-ts-" + [guid]::NewGuid().ToString('N') + '.txt')
        Set-Content -LiteralPath $scratch -Value 'domovoy' -Encoding UTF8
        # Pin the "previous" stamps to known values first, so the undo can be
        # asserted exactly.
        $previousCreation = [DateTime]::Parse('2020-06-01T12:00:00Z').ToUniversalTime()
        $previousWrite = [DateTime]::Parse('2021-08-02T09:15:00Z').ToUniversalTime()
        [System.IO.File]::SetCreationTimeUtc($scratch, $previousCreation)
        [System.IO.File]::SetLastWriteTimeUtc($scratch, $previousWrite)

        $manifest = Join-Path -Path $script:v12ManifestDir -ChildPath 'v12.stamp.apply.json'
        @{
            id = 'v12.stamp.apply'
            title = 'V12 fixture: pin the scratch stamps'
            version = '1.2.0'
            category = 'maintenance'
            risk = 'low'
            description = 'Test fixture: sets creation and last-write stamps, then undo restores them.'
            ops = @( @{ type = 'file.timestamp'; path = $scratch; creation = '2024-01-15T10:30:00Z'; lastWrite = '2024-01-15T10:30:00Z' } )
            undo = @{ mode = 'snapshot' }
            verify = @( @{ type = 'file.timestamp'; path = $scratch; creation = '2024-01-15T10:30:00Z'; lastWrite = '2024-01-15T10:30:00Z' } )
            references = @('https://learn.microsoft.com/windows/win32/sysinfo/registry')
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifest -Encoding UTF8

        $applied = Invoke-DomovoyFeature -ManifestFile $manifest -Apply -SkipRestorePoint
        $applied.Mode | Should -Be 'Apply'
        $applied.Verification.AllPass | Should -BeTrue
        # The instant was set exactly, even though the probe compared the Z
        # spelling with the round-trip 'o' spelling.
        (Get-Item -LiteralPath $scratch).CreationTimeUtc | Should -Be ([DateTime]::Parse('2024-01-15T10:30:00Z').ToUniversalTime())

        $undo = Undo-DomovoyFeature -Id v12.stamp.apply -Apply
        $undo.Mode | Should -Be 'Undo'
        (Get-Item -LiteralPath $scratch).CreationTimeUtc | Should -Be $previousCreation
        (Get-Item -LiteralPath $scratch).LastWriteTimeUtc | Should -Be $previousWrite

        Remove-Item -LiteralPath $scratch -Force -ErrorAction SilentlyContinue
    }

    It 'a missing path fails the apply honestly, allowMissing skips and the probe answers FAIL' -Skip:(-not $script:isWindowsPlatform) {
        $ghost = 'C:\Windows\Temp\domovoy-v12-ghost-' + [guid]::NewGuid().ToString('N') + '.txt'

        $strict = Join-Path -Path $script:v12ManifestDir -ChildPath 'v12.stamp.strict.json'
        @{
            id = 'v12.stamp.strict'
            title = 'V12 fixture: missing path without allowMissing'
            version = '1.2.0'
            category = 'maintenance'
            risk = 'low'
            description = 'Test fixture: a missing path fails the apply without allowMissing.'
            ops = @( @{ type = 'file.timestamp'; path = $ghost; creation = '2024-01-15T10:30:00Z' } )
            undo = @{ mode = 'snapshot' }
            verify = @( @{ type = 'file.timestamp'; path = $ghost; creation = '2024-01-15T10:30:00Z' } )
            references = @('https://learn.microsoft.com/windows/win32/sysinfo/registry')
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $strict -Encoding UTF8
        { Invoke-DomovoyFeature -ManifestFile $strict -Apply -SkipRestorePoint } | Should -Throw

        $lenient = Join-Path -Path $script:v12ManifestDir -ChildPath 'v12.stamp.lenient.json'
        @{
            id = 'v12.stamp.lenient'
            title = 'V12 fixture: missing path with allowMissing'
            version = '1.2.0'
            category = 'maintenance'
            risk = 'low'
            description = 'Test fixture: a missing path is skipped with allowMissing, the probe fails honestly.'
            ops = @( @{ type = 'file.timestamp'; path = $ghost; creation = '2024-01-15T10:30:00Z'; allowMissing = $true } )
            undo = @{ mode = 'snapshot' }
            verify = @( @{ type = 'file.timestamp'; path = $ghost; creation = '2024-01-15T10:30:00Z' } )
            references = @('https://learn.microsoft.com/windows/win32/sysinfo/registry')
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $lenient -Encoding UTF8

        $applied = Invoke-DomovoyFeature -ManifestFile $lenient -Apply -SkipRestorePoint
        $applied.Mode | Should -Be 'Apply'
        $applied.Verification.AllPass | Should -BeFalse
        $applied.Verification.Results[0].Actual | Should -Be '<missing>'
    }
}

Describe 'Documented catalog wave (80/82/86/74)' {
    It 'each new manifest dry-runs as a registry plan without touching anything' {
        foreach ($id in @('ui.taskbaralign.left', 'ui.visualfx.performance', 'ui.visualfx.appearance', 'policy.doh.auto.disabled', 'policy.office.telemetry.off')) {
            $dry = Invoke-DomovoyFeature -Id $id
            $dry.Mode | Should -Be 'DryRun'
            $dry.Plan[0].Op | Should -Be 'registry.set'
            $dry.Plan[0].NewType | Should -Be 'DWord'
        }
    }

    It 'the Office manifest carries both documented policy values' {
        $dry = Invoke-DomovoyFeature -Id policy.office.telemetry.off
        @($dry.Plan).Count | Should -Be 2
        $dry.Plan[0].Target | Should -Match 'clienttelemetry\\SendTelemetry'
        $dry.Plan[1].Target | Should -Match 'clienttelemetry\\DisableTelemetry'
    }
}

Describe 'Driver rollback report (catalog 90)' -Skip:(-not $script:isWindowsPlatform) {
    It 'flags drivers with an older package in the store and is honest about the rest' {
        InModuleScope Domovoy {
            Mock Get-WindowsDriver {
                @(
                    [pscustomobject]@{ Driver = 'oem12.inf'; OriginalFileName = 'C:\Windows\INF\nvlt.inf'; ClassName = 'Display'; ProviderName = 'NVIDIA'; Date = [datetime]'2024-05-01'; Version = '31.0.15.3623'; Inbox = $false }
                    [pscustomobject]@{ Driver = 'oem7.inf';  OriginalFileName = 'C:\Windows\INF\nvlt.inf'; ClassName = 'Display'; ProviderName = 'NVIDIA'; Date = [datetime]'2024-03-01'; Version = '31.0.15.3601'; Inbox = $false }
                    [pscustomobject]@{ Driver = 'oem3.inf';  OriginalFileName = 'C:\Windows\INF\audio.inf'; ClassName = 'MEDIA';    ProviderName = 'Contoso'; Date = [datetime]'2023-11-11'; Version = '1.0.0.1'; Inbox = $false }
                )
            }
        }
        $report = Get-DomovoyDriverRollbackReport
        $report.DriverPackages | Should -Be 3
        $report.DriverGroups | Should -Be 2
        $report.RollbackReady | Should -Be 1

        $ready = @($report.Groups | Where-Object { $_.RollbackReady })
        $ready[0].InfName | Should -Be 'nvlt.inf'
        $ready[0].ActiveOemDriver | Should -Be 'oem12.inf'
        $ready[0].ActiveVersion | Should -Be '31.0.15.3623'
        $ready[0].OlderPackages[0] | Should -BeLike 'oem7.inf*'

        $single = @($report.Groups | Where-Object { -not $_.RollbackReady })
        $single[0].InfName | Should -Be 'audio.inf'
        @($single[0].OlderPackages).Count | Should -Be 0
    }
}

Describe 'Component store cleanup (catalog 88)' -Skip:(-not $script:isWindowsPlatform) {
    BeforeAll {
        $script:v12WinSxS = Join-Path -Path $env:SystemRoot -ChildPath 'WinSxS'
    }

    It 'the dry-run measures the store and reports the task state' {
        InModuleScope Domovoy {
            Mock Get-ChildItem -ParameterFilter { $LiteralPath -and $LiteralPath -like '*WinSxS' } {
                @(
                    [pscustomobject]@{ Length = [long]100 }
                    [pscustomobject]@{ Length = [long]200 }
                )
            }
            Mock Get-ScheduledTask {
                [pscustomobject]@{ TaskPath = '\Microsoft\Windows\Servicing\'; TaskName = 'StartComponentCleanup'; State = 'Ready' }
            }
        }
        $dry = Invoke-DomovoyComponentStoreCleanup
        $dry.Mode | Should -Be 'DryRun'
        $dry.WinSxSBytes | Should -Be 300
        $dry.TaskState | Should -Be 'Ready'
        $dry.Note | Should -BeLike '*ResetBase*'
    }

    It 'apply triggers the built-in task, journals it, and the chain stays verifiable' {
        InModuleScope Domovoy {
            Mock Get-ChildItem -ParameterFilter { $LiteralPath -and $LiteralPath -like '*WinSxS' } {
                @([pscustomobject]@{ Length = [long]100 })
            }
            Mock Get-ScheduledTask {
                [pscustomobject]@{ TaskPath = '\Microsoft\Windows\Servicing\'; TaskName = 'StartComponentCleanup'; State = 'Ready' }
            }
            Mock Start-ScheduledTask { param($TaskPath, $TaskName) $script:v12Triggered = "$TaskPath$TaskName" }
            Mock New-DomovoyRestorePoint { }
            Mock Test-DomovoyAdmin { return $true }
        }
        $result = Invoke-DomovoyComponentStoreCleanup -Apply -SkipRestorePoint
        $result.Mode | Should -Be 'Apply'
        $result.Triggered | Should -BeTrue
        $result.TaskPath | Should -Be '\Microsoft\Windows\Servicing\'
        InModuleScope Domovoy { $script:v12Triggered } | Should -Be '\Microsoft\Windows\Servicing\StartComponentCleanup'

        $ledger = Join-Path -Path $env:DOMOVOY_STORE -ChildPath 'ledger.jsonl'
        (Get-Content -LiteralPath $ledger -Raw) | Should -Match 'componentstore\.apply'
        $integrity = Test-DomovoyLedgerIntegrity
        $integrity.ChainState | Should -Be 'ok'
    }

    It 'a missing servicing task refuses to trigger anything (backup gate)' {
        InModuleScope Domovoy {
            Mock Get-ScheduledTask { return $null }
            Mock Start-ScheduledTask { }
            Mock Test-DomovoyAdmin { return $true }
        }
        { Invoke-DomovoyComponentStoreCleanup -Apply -SkipRestorePoint } | Should -Throw
    }
}
