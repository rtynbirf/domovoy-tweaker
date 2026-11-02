BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $env:DOMOVOY_STORE = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("domovoy-loop-" + [guid]::NewGuid().ToString('N'))
    $env:DOMOVOY_FEATURES_DIR = Join-Path -Path $repoRoot -ChildPath 'config/features'
    Import-Module (Join-Path -Path $repoRoot -ChildPath 'src/Domovoy/Domovoy.psd1') -Force

    $script:testRoot = 'HKCU:\Software\DomovoyCI\' + [guid]::NewGuid().ToString('N').Substring(0, 8)
    New-Item -Path $script:testRoot -ItemType Directory -Force | Out-Null

    $script:manifestDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("domovoy-manifests-" + [guid]::NewGuid().ToString('N'))
    New-Item -Path $script:manifestDir -ItemType Directory -Force | Out-Null

    $script:registryRef = 'https://learn.microsoft.com/windows/win32/sysinfo/registry'

    $setManifest = Join-Path -Path $script:manifestDir -ChildPath 'test-set.json'
    @{
        id = 'test.set.value'
        title = 'Test fixture: set registry value'
        version = '1.0.0'
        category = 'core'
        risk = 'low'
        description = 'Test fixture: sets a DWORD value on a temporary registry key.'
        ops = @(@{ type = 'registry.set'; path = $script:testRoot; name = 'TestValue'; value = 42; valueType = 'DWord' })
        undo = @{ mode = 'snapshot' }
        verify = @(@{ type = 'registry.set'; path = $script:testRoot; name = 'TestValue'; value = 42 })
        references = @($script:registryRef)
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $setManifest -Encoding UTF8

    $deleteManifest = Join-Path -Path $script:manifestDir -ChildPath 'test-delete.json'
    @{
        id = 'test.delete.value'
        title = 'Test fixture: delete registry value'
        version = '1.0.0'
        category = 'core'
        risk = 'low'
        description = 'Test fixture: deletes a DWORD value from a temporary registry key.'
        ops = @(@{ type = 'registry.delete'; path = $script:testRoot; name = 'TestValue' })
        undo = @{ mode = 'snapshot' }
        verify = @(@{ type = 'registry.absent'; path = $script:testRoot; name = 'TestValue' })
        references = @($script:registryRef)
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $deleteManifest -Encoding UTF8

    $stopManifest = Join-Path -Path $script:manifestDir -ChildPath 'test-stop.json'
    @{
        id = 'test.stop.service'
        title = 'Test fixture: stop a service'
        version = '1.0.0'
        category = 'core'
        risk = 'high'
        description = 'Test fixture: stops a service; used only in dry-run during tests.'
        ops = @(@{ type = 'service.stop'; name = 'DiagTrack' })
        undo = @{ mode = 'snapshot' }
        verify = @(@{ type = 'service.status'; name = 'DiagTrack'; expected = 'Stopped' })
        references = @('https://learn.microsoft.com/windows/privacy/configure-windows-telemetry-in-your-organization')
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $stopManifest -Encoding UTF8

    # Fixture file for file.attribute roundtrip tests.
    $script:testFile = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("domovoy-file-" + [guid]::NewGuid().ToString('N') + ".txt")
    Set-Content -LiteralPath $script:testFile -Value 'domovoy' -Encoding ASCII

    # Fixture root for the registry key creation test (intentionally NOT created:
    # apply must create the whole chain, undo must remove it again).
    $script:keyRoot = 'HKCU:\Software\DomovoyCI\' + [guid]::NewGuid().ToString('N').Substring(0, 8)

    $attributeManifest = Join-Path -Path $script:manifestDir -ChildPath 'test-attribute.json'
    @{
        id = 'test.attribute.file'
        title = 'Test fixture: set file attributes'
        version = '1.0.0'
        category = 'core'
        risk = 'low'
        description = 'Test fixture: adds the Hidden attribute to a temporary file.'
        ops = @(@{ type = 'file.attribute'; path = $script:testFile; attributes = @('Hidden') })
        undo = @{ mode = 'snapshot' }
        verify = @(@{ type = 'file.attributes'; path = $script:testFile; attributes = @('Hidden') })
        references = @($script:registryRef)
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $attributeManifest -Encoding UTF8

    $keyManifest = Join-Path -Path $script:manifestDir -ChildPath 'test-key-create.json'
    @{
        id = 'test.key.create'
        title = 'Test fixture: set a value in a not-yet-existing key'
        version = '1.0.0'
        category = 'core'
        risk = 'low'
        description = 'Test fixture: sets a DWORD in a registry key that does not exist yet.'
        ops = @(@{ type = 'registry.set'; path = "$script:keyRoot\level1\level2"; name = 'LeafValue'; value = 5; valueType = 'DWord' })
        undo = @{ mode = 'snapshot' }
        verify = @(@{ type = 'registry.set'; path = "$script:keyRoot\level1\level2"; name = 'LeafValue'; value = 5 })
        references = @($script:registryRef)
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $keyManifest -Encoding UTF8

    $appxManifest = Join-Path -Path $script:manifestDir -ChildPath 'test-appx.json'
    @{
        id = 'test.appx.remove'
        title = 'Test fixture: remove an appx package'
        version = '1.0.0'
        category = 'core'
        risk = 'medium'
        description = 'Test fixture: removes a package that does not exist; used only in dry-run during tests.'
        ops = @(@{ type = 'appx.remove'; name = 'Domovoy.Test.NonexistentPackage' })
        undo = @{ mode = 'snapshot' }
        verify = @(@{ type = 'appx.absent'; name = 'Domovoy.Test.NonexistentPackage' })
        references = @($script:registryRef)
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $appxManifest -Encoding UTF8

    # Fixture scheduled task for the v0.4 scheduler.task roundtrip.
    $script:taskName = 'DomovoyCI-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
    $script:taskFixture = $false
    try {
        $action = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument '/c exit 0'
        $trigger = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddDays(365))
        $null = Register-ScheduledTask -TaskName $script:taskName -Action $action -Trigger $trigger -ErrorAction Stop
        $script:taskFixture = $true
    }
    catch {
        Write-Warning ("Scheduled task fixture was not registered: {0}" -f $_.Exception.Message)
    }

    $schedulerManifest = Join-Path -Path $script:manifestDir -ChildPath 'test-scheduler.json'
    @{
        id = 'test.scheduler.disable'
        title = 'Test fixture: disable a scheduled task'
        version = '1.0.0'
        category = 'core'
        risk = 'medium'
        description = 'Test fixture: disables a task created by the test run itself.'
        ops = @(@{ type = 'scheduler.task'; taskPath = '\'; taskName = $script:taskName })
        undo = @{ mode = 'snapshot' }
        verify = @(@{ type = 'scheduler.taskState'; taskPath = '\'; taskName = $script:taskName; expected = 'Disabled' })
        references = @($script:registryRef)
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $schedulerManifest -Encoding UTF8
}

AfterAll {
    Remove-Module -Name Domovoy -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $script:testRoot) {
        Remove-Item -LiteralPath $script:testRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $script:keyRoot) {
        Remove-Item -LiteralPath $script:keyRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $script:testFile) {
        Remove-Item -LiteralPath $script:testFile -Force -ErrorAction SilentlyContinue
    }
    if ($script:taskFixture) {
        Unregister-ScheduledTask -TaskName $script:taskName -Confirm:$false -ErrorAction SilentlyContinue
    }
    if ($env:DOMOVOY_STORE -and (Test-Path -LiteralPath $env:DOMOVOY_STORE)) {
        Remove-Item -LiteralPath $env:DOMOVOY_STORE -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'v0.2 ledger loop (apply - verify - undo)' {

    It 'apply on absent value creates it; undo removes it because it was absent before' {
        $before = Get-ItemProperty -LiteralPath $script:testRoot -Name 'TestValue' -ErrorAction SilentlyContinue
        $before | Should -BeNullOrEmpty

        $applied = Invoke-DomovoyFeature -ManifestFile (Join-Path $script:manifestDir 'test-set.json') -Apply -SkipRestorePoint
        $applied.Mode | Should -Be 'Apply'
        $applied.Verification.AllPass | Should -BeTrue
        (Get-ItemProperty -LiteralPath $script:testRoot -Name 'TestValue').TestValue | Should -Be 42

        $undo = Undo-DomovoyFeature -Id 'test.set.value' -Apply
        $undo.Mode | Should -Be 'Undo'
        $afterUndo = Get-ItemProperty -LiteralPath $script:testRoot -Name 'TestValue' -ErrorAction SilentlyContinue
        $afterUndo | Should -BeNullOrEmpty
    }

    It 'apply delete removes an existing value; undo restores the exact value and type' {
        Set-ItemProperty -LiteralPath $script:testRoot -Name 'TestValue' -Value 7 -Type DWord

        $applied = Invoke-DomovoyFeature -ManifestFile (Join-Path $script:manifestDir 'test-delete.json') -Apply -SkipRestorePoint
        $applied.Mode | Should -Be 'Apply'
        $applied.Verification.AllPass | Should -BeTrue
        Get-ItemProperty -LiteralPath $script:testRoot -Name 'TestValue' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty

        $undo = Undo-DomovoyFeature -Id 'test.delete.value' -Apply
        $undo.Mode | Should -Be 'Undo'
        (Get-ItemProperty -LiteralPath $script:testRoot -Name 'TestValue').TestValue | Should -Be 7
        (Get-Item -LiteralPath $script:testRoot).GetValueKind('TestValue') | Should -Be 'DWord'
    }

    It 'undo dry-run shows the snapshot without changing anything' {
        Set-ItemProperty -LiteralPath $script:testRoot -Name 'TestValue' -Value 7 -Type DWord

        $dryApply = Invoke-DomovoyFeature -ManifestFile (Join-Path $script:manifestDir 'test-delete.json')
        $dryApply.Mode | Should -Be 'DryRun'
        (Get-ItemProperty -LiteralPath $script:testRoot -Name 'TestValue').TestValue | Should -Be 7

        $dryUndo = Undo-DomovoyFeature -Id 'test.delete.value'
        $dryUndo.Mode | Should -Be 'DryRun'
        @($dryUndo.Snapshot).Count | Should -BeGreaterThan 0
        (Get-ItemProperty -LiteralPath $script:testRoot -Name 'TestValue').TestValue | Should -Be 7
    }

    It 'service.stop dry-run builds a plan without touching the service' {
        $dry = Invoke-DomovoyFeature -ManifestFile (Join-Path $script:manifestDir 'test-stop.json')
        $dry.Mode | Should -Be 'DryRun'
        $dry.Plan[0].Op | Should -Be 'service.stop'
        @($dry.Plan).Count | Should -Be 1
    }

    It 'apply file.attribute adds the attribute; undo restores the exact previous set' {
        # -Force everywhere: after apply the fixture is Hidden, and Get-Item
        # cannot see hidden files without it (same reason the module needs it).
        $before = [string](Get-Item -LiteralPath $script:testFile -Force).Attributes

        $applied = Invoke-DomovoyFeature -ManifestFile (Join-Path $script:manifestDir 'test-attribute.json') -Apply -SkipRestorePoint
        $applied.Mode | Should -Be 'Apply'
        $applied.Verification.AllPass | Should -BeTrue
        ((Get-Item -LiteralPath $script:testFile -Force).Attributes -band [System.IO.FileAttributes]::Hidden) | Should -Not -Be 0

        $undo = Undo-DomovoyFeature -Id 'test.attribute.file' -Apply
        $undo.Mode | Should -Be 'Undo'
        [string](Get-Item -LiteralPath $script:testFile -Force).Attributes | Should -Be $before
    }

    It 'apply creates the registry key chain; undo removes the value and the created empty keys' {
        Test-Path -LiteralPath $script:keyRoot | Should -BeFalse

        $applied = Invoke-DomovoyFeature -ManifestFile (Join-Path $script:manifestDir 'test-key-create.json') -Apply -SkipRestorePoint
        $applied.Mode | Should -Be 'Apply'
        $applied.Verification.AllPass | Should -BeTrue
        (Get-ItemProperty -LiteralPath "$script:keyRoot\level1\level2").LeafValue | Should -Be 5

        $undo = Undo-DomovoyFeature -Id 'test.key.create' -Apply
        $undo.Mode | Should -Be 'Undo'
        Test-Path -LiteralPath "$script:keyRoot\level1\level2" | Should -BeFalse
        Test-Path -LiteralPath "$script:keyRoot\level1" | Should -BeFalse
        Test-Path -LiteralPath $script:keyRoot | Should -BeFalse
    }

    It 'appx dry-run builds a plan without touching anything' {
        $dry = Invoke-DomovoyFeature -ManifestFile (Join-Path $script:manifestDir 'test-appx.json')
        $dry.Mode | Should -Be 'DryRun'
        $dry.Plan[0].Op | Should -Be 'appx.remove'
        $dry.Plan[0].Current | Should -Be '<missing>'
    }

    It 'ledger records featureSource and survives a torn line' {
        # Self-contained: a fresh store guarantees the genesis entry exists.
        $oldStore = $env:DOMOVOY_STORE
        $env:DOMOVOY_STORE = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("domovoy-ledger-" + [guid]::NewGuid().ToString('N'))
        try {
            $ledgerPath = (Initialize-Domovoy).Ledger
            Set-ItemProperty -LiteralPath $script:testRoot -Name 'TestValue' -Value 7 -Type DWord
            $applied = Invoke-DomovoyFeature -ManifestFile (Join-Path $script:manifestDir 'test-delete.json') -Apply -SkipRestorePoint
            $applied.Mode | Should -Be 'Apply'
            $undo = Undo-DomovoyFeature -Id 'test.delete.value' -Apply
            $undo.Mode | Should -Be 'Undo'

            $applies = @(Get-DomovoyLedger -Event 'feature.apply' -Last 1000000)
            $applies.Count | Should -BeGreaterThan 0
            $applies[0].featureSource | Should -Not -BeNullOrEmpty

            Add-Content -LiteralPath $ledgerPath -Value '{broken json line...'

            $entries = @(Get-DomovoyLedger -Last 1000000)
            $entries.Count | Should -BeGreaterThan $applies.Count
            $entries.event | Should -Contain 'ledger.init'
            $entries.event | Should -Contain 'feature.apply'
            $entries.event | Should -Contain 'feature.undo'
        }
        finally {
            if (Test-Path -LiteralPath $env:DOMOVOY_STORE) {
                Remove-Item -LiteralPath $env:DOMOVOY_STORE -Recurse -Force -ErrorAction SilentlyContinue
            }
            $env:DOMOVOY_STORE = $oldStore
        }
    }

    It 'drift scan resolves manifests from featureSource after a rename' {
        # Simulate a moved manifest: the ledger points at the temp manifest dir,
        # which is not the feature directory. A currently-applied feature is
        # required, because features whose newest ledger event is an undo are
        # not scanned since v0.4.
        $applied = Invoke-DomovoyFeature -ManifestFile (Join-Path $script:manifestDir 'test-set.json') -Apply -SkipRestorePoint
        $applied.Verification.AllPass | Should -BeTrue

        $scan = Invoke-DomovoyDriftScan
        $scan.Scanned | Should -BeGreaterThan 0
        $scan.Report | Should -Not -BeNullOrEmpty
    }
}

Describe 'v0.4 drift sentinel' {

    It 'scan catches a value reverted after apply; the report carries dates and the verified baseline' {
        $applied = Invoke-DomovoyFeature -ManifestFile (Join-Path $script:manifestDir 'test-set.json') -Apply -SkipRestorePoint
        $applied.Verification.AllPass | Should -BeTrue

        # Simulate a Windows update rolling the policy back.
        Set-ItemProperty -LiteralPath $script:testRoot -Name 'TestValue' -Value 43 -Type DWord

        $scan = Invoke-DomovoyDriftScan -FeatureId 'test.set.value'
        $scan.Scanned | Should -Be 1
        $scan.Drifted | Should -Be 1
        $row = @($scan.Report)[0]
        $row.FeatureId | Should -Be 'test.set.value'
        $row.AppliedAt | Should -Not -BeNullOrEmpty
        $row.DetectedAt | Should -Not -BeNullOrEmpty
        $detail = @($row.Details | Where-Object { $_.Target -like '*TestValue' })[0]
        $detail.Verified | Should -Be '42'
        $detail.Expected | Should -Be '42'
        $detail.Actual | Should -Be '43'
        $detail.Pass | Should -BeFalse

        # Restore the verified state, then undo cleanly.
        Set-ItemProperty -LiteralPath $script:testRoot -Name 'TestValue' -Value 42 -Type DWord
        $undo = Undo-DomovoyFeature -Id 'test.set.value' -Apply
        $undo.Mode | Should -Be 'Undo'
    }

    It 'scan skips features whose latest ledger event is an undo' {
        $scan = Invoke-DomovoyDriftScan -FeatureId 'test.set.value'
        $scan.Scanned | Should -Be 0
        $scan.Drifted | Should -Be 0
    }

    It '-Since limits the scan to features applied after the given moment' {
        $applied = Invoke-DomovoyFeature -ManifestFile (Join-Path $script:manifestDir 'test-set.json') -Apply -SkipRestorePoint
        $applied.Verification.AllPass | Should -BeTrue

        $recent = Invoke-DomovoyDriftScan -Since (Get-Date).AddMinutes(-5)
        $recent.Scanned | Should -BeGreaterThan 0

        $future = Invoke-DomovoyDriftScan -Since (Get-Date).AddMinutes(5)
        $future.Scanned | Should -Be 0
    }
}

Describe 'v0.4 scheduler.task roundtrip' {

    It 'dry-run builds a plan without touching the task' -Skip:(-not $script:taskFixture) {
        $dry = Invoke-DomovoyFeature -ManifestFile (Join-Path $script:manifestDir 'test-scheduler.json')
        $dry.Mode | Should -Be 'DryRun'
        $dry.Plan[0].Op | Should -Be 'scheduler.task'
        $dry.Plan[0].Current | Should -Be 'Ready'
        $dry.Plan[0].New | Should -Be 'Disabled'
        (Get-ScheduledTask -TaskPath '\' -TaskName $script:taskName).State | Should -Be 'Ready'
    }

    It 'apply disables the task; undo returns the previous state' -Skip:(-not $script:taskFixture) {
        $applied = Invoke-DomovoyFeature -ManifestFile (Join-Path $script:manifestDir 'test-scheduler.json') -Apply -SkipRestorePoint
        $applied.Mode | Should -Be 'Apply'
        $applied.Verification.AllPass | Should -BeTrue
        (Get-ScheduledTask -TaskPath '\' -TaskName $script:taskName).State | Should -Be 'Disabled'

        $undo = Undo-DomovoyFeature -Id 'test.scheduler.disable' -Apply
        $undo.Mode | Should -Be 'Undo'
        (Get-ScheduledTask -TaskPath '\' -TaskName $script:taskName).State | Should -Be 'Ready'
    }
}

Describe 'v0.4 temp cleanup' {

    It 'dry-run reports volume without deleting; apply removes old files and records the ledger event' {
        $fixture = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("domovoy-cleanup-" + [guid]::NewGuid().ToString('N') + ".txt")
        Set-Content -LiteralPath $fixture -Value 'domovoy-cleanup-fixture' -Encoding ASCII
        (Get-Item -LiteralPath $fixture).LastWriteTime = (Get-Date).AddDays(-400)

        try {
            $dry = Invoke-DomovoyCleanup -Target Temp -OlderThanDays 365
            $dry.Mode | Should -Be 'DryRun'
            $dry.Files | Should -BeGreaterThan 0
            $dry.Bytes | Should -BeGreaterThan 0
            Test-Path -LiteralPath $fixture | Should -BeTrue

            $applied = Invoke-DomovoyCleanup -Target Temp -OlderThanDays 365 -Apply
            $applied.Mode | Should -Be 'Apply'
            $applied.FilesRemoved | Should -BeGreaterThan 0
            Test-Path -LiteralPath $fixture | Should -BeFalse

            $events = @(Get-DomovoyLedger -Event 'cleanup.apply' -Last 10)
            $events.Count | Should -BeGreaterThan 0
            $events[-1].irreversible | Should -BeTrue
        }
        finally {
            if (Test-Path -LiteralPath $fixture) {
                Remove-Item -LiteralPath $fixture -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
