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

    $appxPresentManifest = Join-Path -Path $script:manifestDir -ChildPath 'test-appx-present.json'
    @{
        id = 'test.appx.present'
        title = 'Test fixture: expect an appx package to be present'
        version = '1.0.0'
        category = 'core'
        risk = 'low'
        description = 'Test fixture: the appx.present probe against a package that does not exist.'
        ops = @(@{ type = 'registry.set'; path = $script:testRoot; name = 'AppxProbeMarker'; value = 1; valueType = 'DWord' })
        undo = @{ mode = 'snapshot' }
        verify = @(@{ type = 'appx.present'; name = 'Domovoy.Test.NonexistentPackage' })
        references = @($script:registryRef)
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $appxPresentManifest -Encoding UTF8

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
            # v0.5: the apply report carries the measured before/after numbers.
            $applied.FilesFound | Should -BeGreaterThan 0
            $applied.BytesFound | Should -BeGreaterThan 0
            $applied.FilesFound | Should -BeGreaterOrEqual $applied.FilesRemoved
            $applied.BytesAfter | Should -BeLessThan $applied.BytesFound
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

Describe 'v0.5 effect reports' {

    It 'apply reports what really changed: snapshot before vs probes after' {
        # Self-sufficient: earlier tests may have left the value applied.
        Remove-ItemProperty -LiteralPath $script:testRoot -Name 'TestValue' -ErrorAction SilentlyContinue
        $before = Get-ItemProperty -LiteralPath $script:testRoot -Name 'TestValue' -ErrorAction SilentlyContinue
        $before | Should -BeNullOrEmpty

        $applied = Invoke-DomovoyFeature -ManifestFile (Join-Path $script:manifestDir 'test-set.json') -Apply -SkipRestorePoint
        $applied.Mode | Should -Be 'Apply'

        @($applied.Changes).Count | Should -Be 1
        $row = $applied.Changes[0]
        $row.Probe | Should -Be 'registry.set'
        $row.Before | Should -Be '<unset>'
        $row.After | Should -Be '42'
        $row.Changed | Should -BeTrue

        # A second apply of the same manifest: nothing changes anymore.
        $again = Invoke-DomovoyFeature -ManifestFile (Join-Path $script:manifestDir 'test-set.json') -Apply -SkipRestorePoint
        $again.Changes[0].Before | Should -Be '42'
        $again.Changes[0].After | Should -Be '42'
        $again.Changes[0].Changed | Should -BeFalse

        $undo = Undo-DomovoyFeature -Id 'test.set.value' -Apply
        $undo.Mode | Should -Be 'Undo'
    }

    It 'appx.present probe answers honestly for a missing package' {
        # The probe runs in the real apply/verify contour: the marker op is
        # harmless, the probe fails honestly because the package is absent.
        $applied = Invoke-DomovoyFeature -ManifestFile (Join-Path $script:manifestDir 'test-appx-present.json') -Apply -SkipRestorePoint
        $applied.Mode | Should -Be 'Apply'
        $applied.Verification.AllPass | Should -BeFalse
        @($applied.Verification.Results).Count | Should -Be 1
        $probe = $applied.Verification.Results[0]
        $probe.Probe | Should -Be 'appx.present'
        $probe.Expected | Should -Be '<present>'
        $probe.Actual | Should -Be '<absent>'
        $probe.Pass | Should -BeFalse

        $undo = Undo-DomovoyFeature -Id 'test.appx.present' -Apply
        $undo.Mode | Should -Be 'Undo'
    }

    It 'change report answers from the ledger with dates' {
        $applied = Invoke-DomovoyFeature -ManifestFile (Join-Path $script:manifestDir 'test-set.json') -Apply -SkipRestorePoint
        $applied.Mode | Should -Be 'Apply'

        $report = Get-DomovoyChangeReport -Since (Get-Date).AddMinutes(-5)
        $report.Events | Should -BeGreaterThan 0
        $report.Counts['feature.apply'] | Should -BeGreaterThan 0
        $row = @($report.Report | Where-Object { $_.Event -eq 'feature.apply' })[0]
        $row.Timestamp | Should -Not -BeNullOrEmpty
        $row.FeatureId | Should -Be 'test.set.value'
        $row.Summary | Should -Match 'verified:'

        $future = Get-DomovoyChangeReport -Since (Get-Date).AddMinutes(5)
        $future.Events | Should -Be 0

        $undo = Undo-DomovoyFeature -Id 'test.set.value' -Apply
        $undo.Mode | Should -Be 'Undo'
    }

    It 'memory trim dry-run measures without touching anything' {
        $dry = Invoke-DomovoyMemoryTrim -ProcessId $PID
        $dry.Mode | Should -Be 'DryRun'
        $dry.WorkingSetBytes | Should -BeGreaterThan 0
        $dry.Note | Should -Match 'temporary'
    }

    It 'memory trim apply trims the current process and records measured bytes' {
        $applied = Invoke-DomovoyMemoryTrim -ProcessId $PID -Apply
        $applied.Mode | Should -Be 'Apply'
        $applied.Trimmed | Should -Be 1
        $applied.BytesBefore | Should -BeGreaterThan 0
        $applied.BytesAfter | Should -BeGreaterThan 0
        $applied.Note | Should -Match 'temporary'

        $events = @(Get-DomovoyLedger -Event 'memorytrim.apply' -Last 10)
        $events.Count | Should -BeGreaterThan 0
        $events[-1].bytesBefore | Should -BeGreaterThan 0
    }

    It 'network reset dry-run shows the plan; undo without a reset fails honestly' {
        $dry = Invoke-DomovoyNetworkReset -Target Winsock
        $dry.Mode | Should -Be 'DryRun'
        $dry.Commands | Should -Contain 'netsh winsock reset'
        $dry.Note | Should -Match 'cannot be restored'

        { Undo-DomovoyNetworkReset } | Should -Throw 'No network reset found in the ledger. Nothing to undo.'
    }

    It 'network reset undo restores nothing when nothing disappeared' {
        # A snapshot with empty lists: recorded directly into the ledger the
        # same way the module writes it (append-only JSONL).
        $ledgerPath = Join-Path -Path $env:DOMOVOY_STORE -ChildPath 'ledger.jsonl'
        $entry = @{
            event = 'networkreset.apply'
            featureId = 'network.winsock.reset'
            target = 'Winsock'
            commands = @()
            snapshot = @{ staticIp = @(); dns = @() }
            rebootRecommended = $true
        } | ConvertTo-Json -Depth 6 -Compress
        Add-Content -LiteralPath $ledgerPath -Value $entry -Encoding UTF8

        $undo = Undo-DomovoyNetworkReset
        $undo.RestoredIpAddresses | Should -Be 0
        $undo.RestoredDnsLists | Should -Be 0
        $undo.Note | Should -Match 'not restorable'
    }

    It 'event log cleanup dry-run counts records without clearing' {
        $dry = Invoke-DomovoyEventLogCleanup
        $dry.Mode | Should -Be 'DryRun'
        $dry.EntriesBefore | Should -BeGreaterThan 0
        $dry.Logs | Should -BeGreaterThan 0
        $dry.Report[0].LogName | Should -Not -BeNullOrEmpty
    }

    It 'telemetry report lists actual policy values from privacy manifests' {
        $rows = @(Get-DomovoyTelemetryReport)
        $rows.Count | Should -BeGreaterThan 0
        foreach ($row in $rows) {
            $row.Path | Should -Not -BeNullOrEmpty
            $row.Feature | Should -Not -BeNullOrEmpty
        }
        $rows.Feature | Should -Contain 'policy.telemetry.level0'
    }

    It 'startup inventory lists documented Run/RunOnce entries read-only' {
        $rows = @(Get-DomovoyStartupInventory)
        foreach ($row in $rows) {
            $row.Hive | Should -BeIn @('HKCU', 'HKLM')
            $row.Key | Should -Match 'CurrentVersion\\Run(Once)?$'
            $row.Name | Should -Not -BeNullOrEmpty
        }
    }

    It 'driver inventory lists drivers and exports a JSON snapshot' {
        $rows = @(Get-DomovoyDriverInventory)
        $rows.Count | Should -BeGreaterThan 0
        $rows[0].DeviceName | Should -Not -BeNullOrEmpty

        $export = Get-DomovoyDriverInventory -Export
        $export.Count | Should -BeGreaterThan 0
        Test-Path -LiteralPath $export.ExportedTo | Should -BeTrue
        $parsed = Get-Content -LiteralPath $export.ExportedTo -Raw -Encoding UTF8 | ConvertFrom-Json
        @($parsed.drivers).Count | Should -Be $export.Count
    }

    It 'integrity check dry-run shows the plan without running anything' {
        $dry = Invoke-DomovoySystemIntegrityCheck
        $dry.Mode | Should -Be 'DryRun'
        $dry.Command | Should -Match 'sfc'

        $dryDism = Invoke-DomovoySystemIntegrityCheck -Tool Dism
        $dryDism.Command | Should -Match 'Dism'
    }

    It 'bitlocker status is read-only and honest' {
        if (-not (Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue)) {
            Set-ItResult -Skipped -Because 'BitLocker module is not available on this runner'
            return
        }
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            Set-ItResult -Skipped -Because 'the runner session is not elevated'
            return
        }
        $rows = @(Get-DomovoyBitLockerStatus)
        foreach ($row in $rows) {
            $row.MountPoint | Should -Not -BeNullOrEmpty
            $row.VolumeStatus | Should -Not -BeNullOrEmpty
        }
    }
}
