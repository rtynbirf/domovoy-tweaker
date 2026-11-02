BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $env:DOMOVOY_STORE = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("domovoy-v06-" + [guid]::NewGuid().ToString('N'))
    $env:DOMOVOY_FEATURES_DIR = Join-Path -Path $repoRoot -ChildPath 'config/features'
    Import-Module (Join-Path -Path $repoRoot -ChildPath 'src/Domovoy/Domovoy.psd1') -Force

    $script:manifestDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("domovoy-v06-manifests-" + [guid]::NewGuid().ToString('N'))
    New-Item -Path $script:manifestDir -ItemType Directory -Force | Out-Null

    $script:registryRef = 'https://learn.microsoft.com/windows/win32/sysinfo/registry'
    # Test-DomovoyAdmin is private; resolve it inside the module scope and
    # treat a non-Windows platform as non-admin (the skips then engage).
    $script:isAdmin = $false
    try {
        $script:isAdmin = InModuleScope Domovoy { Test-DomovoyAdmin }
    }
    catch {
        $script:isAdmin = $false
    }
}

AfterAll {
    Remove-Module -Name Domovoy -Force -ErrorAction SilentlyContinue
    if ($env:DOMOVOY_STORE -like "$([System.IO.Path]::GetTempPath())domovoy-v06-*") {
        Remove-Item -LiteralPath $env:DOMOVOY_STORE -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'network.dns op (catalog 34)' {
    BeforeEach {
        # Script-scoped fake DNS state: the mocks below make the whole
        # plan/snapshot/execute/probe/undo contour run against it.
        $script:dnsState = @{
            'Ethernet' = @('192.168.1.1')
            'Wi-Fi'    = @('10.0.0.1')
        }
        Mock Get-NetAdapter {
            @(
                [pscustomobject]@{ Name = 'Ethernet'; Status = 'Up' }
                [pscustomobject]@{ Name = 'Wi-Fi'; Status = 'Up' }
            )
        }
        Mock Get-DnsClientServerAddress {
            param($InterfaceAlias, $AddressFamily)
            $servers = $script:dnsState[$InterfaceAlias]
            if ($null -eq $servers) { return $null }
            [pscustomobject]@{ InterfaceAlias = $InterfaceAlias; ServerAddresses = @($servers) }
        }
        Mock Set-DnsClientServerAddress {
            param($InterfaceAlias, $ServerAddresses, $ResetServerAddresses)
            if ($ResetServerAddresses) {
                $script:dnsState[$InterfaceAlias] = @()
            }
            else {
                $script:dnsState[$InterfaceAlias] = @($ServerAddresses)
            }
        }

        $script:dnsManifest = Join-Path -Path $script:manifestDir -ChildPath 'dns-test.json'
        @{
            id = 'test.network.dns'
            title = 'Test fixture: DNS preset on connected adapters'
            version = '1.0.0'
            category = 'network'
            risk = 'medium'
            description = 'Test fixture: applies a DNS preset to every connected adapter.'
            ops = @(@{ type = 'network.dns'; interfaceAlias = '*'; servers = @('1.1.1.1', '1.0.0.1') })
            undo = @{ mode = 'snapshot' }
            verify = @(@{ type = 'network.dns'; interfaceAlias = '*'; servers = @('1.1.1.1', '1.0.0.1') })
            references = @($script:registryRef)
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $script:dnsManifest -Encoding UTF8
    }

    It 'dry-run shows the per-adapter plan and changes nothing' {
        $dry = Invoke-DomovoyFeature -ManifestFile $script:dnsManifest
        $dry.Mode | Should -Be 'DryRun'
        $plan = @($dry.Plan | Where-Object { $_.Op -eq 'network.dns' })
        $plan.Count | Should -Be 2
        $plan.Current | Should -Not -Contain '1.1.1.1,1.0.0.1'
        $script:dnsState['Ethernet'] | Should -Be '192.168.1.1'
    }

    It 'apply sets the servers, the probe passes honestly' -Skip:(-not $script:isAdmin) {
        $applied = Invoke-DomovoyFeature -ManifestFile $script:dnsManifest -Apply -SkipRestorePoint
        $applied.Mode | Should -Be 'Apply'
        $applied.Verification.AllPass | Should -BeTrue
        $script:dnsState['Ethernet'] | Should -Be @('1.1.1.1', '1.0.0.1')
        $script:dnsState['Wi-Fi'] | Should -Be @('1.1.1.1', '1.0.0.1')
    }

    It 'undo restores the previous per-adapter server lists' -Skip:(-not $script:isAdmin) {
        $null = Invoke-DomovoyFeature -ManifestFile $script:dnsManifest -Apply -SkipRestorePoint
        $null = Undo-DomovoyFeature -Id 'test.network.dns' -Apply
        $script:dnsState['Ethernet'] | Should -Be @('192.168.1.1')
        $script:dnsState['Wi-Fi'] | Should -Be @('10.0.0.1')
    }
}

Describe 'Token privileges (catalog 52)' -Skip:(-not $script:isAdmin) {
    It 'lists the privileges of the current token, read only' {
        $list = @(Get-DomovoyPrivilege)
        $list.Count | Should -BeGreaterThan 0
        $list[0].PSObject.Properties['Name'] | Should -Not -BeNullOrEmpty
        $list[0].State | Should -BeIn @('Enabled', 'Disabled')
    }

    It 'enables and disables a held privilege with a ledger record each time' {
        $name = 'SeTakeOwnershipPrivilege'
        $dry = Enable-DomovoyPrivilege -Name $name
        $dry.Mode | Should -Be 'DryRun'

        $on = Enable-DomovoyPrivilege -Name $name -Apply
        $on.State | Should -Be 'Enabled'
        @(Get-DomovoyPrivilege | Where-Object { $_.Name -eq $name }).State | Should -Be 'Enabled'

        $off = Disable-DomovoyPrivilege -Name $name -Apply
        $off.State | Should -Be 'Disabled'
        @(Get-DomovoyPrivilege | Where-Object { $_.Name -eq $name }).State | Should -Be 'Disabled'

        $events = @(Get-DomovoyLedger | Where-Object { $_.event -in @('privilege.enable', 'privilege.disable') })
        ($events | Where-Object { $_.privilege -eq $name -and $_.event -eq 'privilege.enable' }).Count | Should -BeGreaterThan 0
        ($events | Where-Object { $_.privilege -eq $name -and $_.event -eq 'privilege.disable' }).Count | Should -BeGreaterThan 0
    }
}

Describe 'File owner (catalog 48)' -Skip:(-not $script:isAdmin) {
    It 'dry-run shows the plan, apply changes the owner, undo restores it' {
        $file = Join-Path -Path (Get-PSDrive TestDrive).Root -ChildPath 'owner-test.txt'
        Set-Content -LiteralPath $file -Value 'x'
        $original = (Get-Acl -LiteralPath $file).Owner
        $target = 'BUILTIN\Administrators'
        if ($original -eq $target) { $target = 'NT AUTHORITY\SYSTEM' }

        $dry = Set-DomovoyFileOwner -Path $file -Owner $target
        $dry.Mode | Should -Be 'DryRun'
        (Get-Acl -LiteralPath $file).Owner | Should -Be $original

        $applied = Set-DomovoyFileOwner -Path $file -Owner $target -Apply
        $applied.Verified | Should -BeTrue
        (Get-Acl -LiteralPath $file).Owner | Should -Be $target

        $undone = Undo-DomovoyFileOwner -Apply
        $undone.Mode | Should -Be 'Undo'
        (Get-Acl -LiteralPath $file).Owner | Should -Be $original
    }
}

Describe 'File attribute clearing (catalog 47)' {
    It 'dry-run shows what would be cleared, apply clears only those flags' {
        $file = Join-Path -Path (Get-PSDrive TestDrive).Root -ChildPath 'attr-test.txt'
        Set-Content -LiteralPath $file -Value 'x'
        $item = Get-Item -LiteralPath $file -Force
        $item.Attributes = [System.IO.FileAttributes]'Hidden, ReadOnly'

        $dry = Invoke-DomovoyFileAttributeClear -Path $file -Attributes 'Hidden'
        $dry.Mode | Should -Be 'DryRun'
        $dry.Plan[0].WouldClear | Should -Be 'Hidden'

        $applied = Invoke-DomovoyFileAttributeClear -Path $file -Attributes 'Hidden' -Apply
        $applied.Verified | Should -BeTrue
        $after = Get-Item -LiteralPath $file -Force
        ($after.Attributes -band [System.IO.FileAttributes]::Hidden) | Should -Be 0
        ($after.Attributes -band [System.IO.FileAttributes]::ReadOnly) | Should -Not -Be 0

        $null = Undo-DomovoyFileAttributeClear -Apply
        $restored = Get-Item -LiteralPath $file -Force
        ($restored.Attributes -band [System.IO.FileAttributes]::Hidden) | Should -Not -Be 0
        ($restored.Attributes -band [System.IO.FileAttributes]::ReadOnly) | Should -Not -Be 0
    }
}

Describe 'BitLocker key backup (catalog 50)' {
    BeforeEach {
        $script:recoveryPassword = '111111-222222-333333-444444-555555-666666-777777-888888'
        Mock Get-BitLockerVolume {
            param($MountPoint)
            [pscustomobject]@{
                MountPoint = $MountPoint
                VolumeStatus = 'FullyEncrypted'
                KeyProtector = @(
                    [pscustomobject]@{ KeyProtectorId = '{TPM-GUID}'; KeyProtectorType = 'Tpm' }
                    [pscustomobject]@{ KeyProtectorId = '{RECOVERY-GUID}'; KeyProtectorType = 'RecoveryPassword'; RecoveryPassword = $script:recoveryPassword }
                )
            }
        }
    }

    It 'dry-run shows protectors but never the key' -Skip:(-not $script:isAdmin) {
        $outFile = Join-Path -Path (Get-PSDrive TestDrive).Root -ChildPath 'key-dry.txt'
        $dry = Backup-DomovoyBitLockerKey -MountPoint 'C:' -OutFile $outFile
        $dry.Mode | Should -Be 'DryRun'
        $dry.RecoveryProtectors | Should -Be 1
        Test-Path -LiteralPath $outFile | Should -BeFalse
        ($dry | ConvertTo-Json -Depth 6) -notmatch [regex]::Escape($script:recoveryPassword) | Should -BeTrue
    }

    It 'apply writes the key to the file only, the ledger never sees it' -Skip:(-not $script:isAdmin) {
        $outFile = Join-Path -Path (Get-PSDrive TestDrive).Root -ChildPath 'key-real.txt'
        $applied = Backup-DomovoyBitLockerKey -MountPoint 'C:' -OutFile $outFile -Apply
        $applied.Mode | Should -Be 'Apply'
        Test-Path -LiteralPath $outFile | Should -BeTrue
        (Get-Content -LiteralPath $outFile -Raw) -match [regex]::Escape($script:recoveryPassword) | Should -BeTrue

        ($applied | ConvertTo-Json -Depth 6) -notmatch [regex]::Escape($script:recoveryPassword) | Should -BeTrue

        $event = @(Get-DomovoyLedger | Where-Object { $_.event -eq 'bitlocker.keybackup' }) | Select-Object -Last 1
        $event | Should -Not -BeNullOrEmpty
        $event.mountPoint | Should -Be 'C:'
        ($event | ConvertTo-Json -Depth 6) -notmatch [regex]::Escape($script:recoveryPassword) | Should -BeTrue
    }
}

Describe 'Driver dedup (catalog 43/46)' {
    It 'ConvertTo-DomovoyCab packs a directory into a real .cab' -Skip:(-not $script:isAdmin) {
        $src = Join-Path -Path (Get-PSDrive TestDrive).Root -ChildPath 'cab-src\nested'
        New-Item -ItemType Directory -Force -Path $src | Out-Null
        Set-Content -LiteralPath (Join-Path $src 'a.inf') -Value 'x'
        Set-Content -LiteralPath (Join-Path $src 'a.sys') -Value 'x'
        $cab = Join-Path -Path (Get-PSDrive TestDrive).Root -ChildPath 'out\backup.cab'

        InModuleScope Domovoy {
            param($Src, $Cab)
            $null = ConvertTo-DomovoyCab -SourceDirectory $Src -DestinationFile $Cab
        } -Parameters @{ Src = (Split-Path -Parent $src); Cab = $cab }

        (Get-Item -LiteralPath $cab).Length | Should -BeGreaterThan 0
    }

    It 'dry-run reports candidates, apply backs up first and removes only old copies' -Skip:(-not $script:isAdmin) {
        Mock Get-WindowsDriver {
            @(
                [pscustomobject]@{ Driver = 'oem10.inf'; OriginalFileName = 'nvlt.inf'; ProviderName = 'NV'; ClassName = 'Display'; ClassGuid = '{4d36e968-e325-11ce-bfc1-08002be10318}'; Version = '27.21.14.1000'; Date = [datetime]'2020-01-01' }
                [pscustomobject]@{ Driver = 'oem11.inf'; OriginalFileName = 'nvlt.inf'; ProviderName = 'NV'; ClassName = 'Display'; ClassGuid = '{4d36e968-e325-11ce-bfc1-08002be10318}'; Version = '27.21.14.2000'; Date = [datetime]'2021-01-01' }
                [pscustomobject]@{ Driver = 'oem20.inf'; OriginalFileName = 'audc.inf'; ProviderName = 'AU'; ClassName = 'MEDIA'; ClassGuid = '{4d36e96c-e325-11ce-bfc1-08002be10318}'; Version = '1.0.0.5'; Date = [datetime]'2019-01-01' }
            )
        }
        $script:pnputilCalls = @()
        Mock pnputil {
            $script:pnputilCalls += ($args -join ' ')
            $LASTEXITCODE = 0
            if ($args[0] -eq '/export-driver') {
                $dest = $args[2]
                New-Item -ItemType Directory -Force -Path (Join-Path $dest 'nvlt') | Out-Null
                Set-Content -LiteralPath (Join-Path $dest 'nvlt\nvlt.inf') -Value 'x'
                Set-Content -LiteralPath (Join-Path $dest 'nvlt\nvlt.sys') -Value 'x'
            }
        }

        $dry = Invoke-DomovoyDriverDedup
        $dry.Mode | Should -Be 'DryRun'
        $dry.DuplicateGroups | Should -Be 1
        @($dry.Candidates).Count | Should -Be 1
        $dry.Candidates[0].Driver | Should -Be 'oem10.inf'
        $dry.Candidates[0].KeepDriver | Should -Be 'oem11.inf'

        $backupDir = Join-Path -Path (Get-PSDrive TestDrive).Root -ChildPath 'dedup-backup'
        $applied = Invoke-DomovoyDriverDedup -Apply -BackupDirectory $backupDir

        # The backup gate ran before any removal.
        $exportIndex = [array]::IndexOf($script:pnputilCalls, ($script:pnputilCalls | Where-Object { $_ -like '/export-driver*' })[0])
        $deleteIndex = [array]::IndexOf($script:pnputilCalls, ($script:pnputilCalls | Where-Object { $_ -like '/delete-driver*' })[0])
        $exportIndex | Should -BeLessThan $deleteIndex

        (Get-Item -LiteralPath $applied.BackupCab).Length | Should -BeGreaterThan 0
        $applied.Removed | Should -Be 'oem10.inf'
        @($applied.Failed).Count | Should -Be 0

        $event = @(Get-DomovoyLedger | Where-Object { $_.event -eq 'driverdedup.apply' }) | Select-Object -Last 1
        $event | Should -Not -BeNullOrEmpty
        $event.backupFiles | Should -BeGreaterThan 0
    }
}

Describe 'Drift auto-heal (catalog 58)' -Skip:(-not $script:isAdmin) {
    It 'dry-run lists candidates, apply heals and stays undoable, the cycle is journaled' {
        $manifest = Join-Path -Path $script:manifestDir -ChildPath 'heal-fixture.json'
        @{
            id = 'test.heal.fixture'
            title = 'Test fixture: healable registry value'
            version = '1.0.0'
            category = 'core'
            risk = 'low'
            description = 'Test fixture: sets a DWORD value that the heal test reverts.'
            ops = @(@{ type = 'registry.set'; path = 'HKCU:\Software\DomovoyV06Heal'; name = 'HealValue'; value = 42; valueType = 'DWord' })
            undo = @{ mode = 'snapshot' }
            verify = @(@{ type = 'registry.set'; path = 'HKCU:\Software\DomovoyV06Heal'; name = 'HealValue'; value = 42 })
            references = @($script:registryRef)
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifest -Encoding UTF8

        $null = Invoke-DomovoyFeature -ManifestFile $manifest -Apply -SkipRestorePoint

        # Simulate drift: a Windows update rolled the policy back.
        Set-ItemProperty -LiteralPath 'HKCU:\Software\DomovoyV06Heal' -Name 'HealValue' -Value 43

        $dry = Invoke-DomovoyAutoHeal -FeatureId 'test.heal.fixture'
        $dry.Mode | Should -Be 'DryRun'
        $dry.WouldHeal | Should -Be 'test.heal.fixture'
        Get-ItemProperty -LiteralPath 'HKCU:\Software\DomovoyV06Heal' | Select-Object -ExpandProperty HealValue | Should -Be 43

        $applied = Invoke-DomovoyAutoHeal -FeatureId 'test.heal.fixture' -Apply
        $applied.Mode | Should -Be 'Apply'
        $applied.Healed | Should -Be 'test.heal.fixture'
        @(Get-DomovoyLedger | Where-Object { $_.event -eq 'autoheal.cycle' -and $_.trigger -eq 'Manual' }).Count | Should -BeGreaterThan 0

        # The heal is a normal feature.apply: undo returns the drifted state.
        $null = Undo-DomovoyFeature -Id 'test.heal.fixture' -Apply
        Get-ItemProperty -LiteralPath 'HKCU:\Software\DomovoyV06Heal' | Select-Object -ExpandProperty HealValue | Should -Be 43
    }
}

Describe 'Watchdog registration (catalog 58)' -Skip:(-not $script:isAdmin) {
    BeforeEach {
        Mock New-ScheduledTaskAction { [pscustomobject]@{ Execute = $Execute; Arguments = $Argument } }
        Mock New-ScheduledTaskTrigger { [pscustomobject]@{ StartBoundary = $At } }
        Mock New-ScheduledTaskSettingsSet { [pscustomobject]@{ StartWhenAvailable = $true } }
        Mock Register-ScheduledTask { $script:registered = $args; [pscustomobject]@{ TaskPath = '\Domovoy\'; TaskName = 'DriftWatchdog' } }
        Mock Get-ScheduledTask {
            param($TaskPath, $TaskName)
            [pscustomobject]@{ TaskPath = $TaskPath; TaskName = $TaskName; State = 'Ready' }
        }
        Mock Unregister-ScheduledTask { $script:unregistered = $args }
    }

    It 'dry-run shows the task definition, apply registers with a journal event' {
        $dry = Register-DomovoyWatchdog
        $dry.Mode | Should -Be 'DryRun'
        $dry.TaskPath | Should -Be '\Domovoy\'
        $dry.Trigger | Should -Be 'Daily at 09:00'

        $applied = Register-DomovoyWatchdog -DailyAt '21:30' -Apply
        $applied.Mode | Should -Be 'Apply'
        $applied.Trigger | Should -Be 'Daily at 21:30'

        Test-Path -LiteralPath $applied.RunnerScript | Should -BeTrue
        $runner = Get-Content -LiteralPath $applied.RunnerScript -Raw
        $runner -match 'Invoke-DomovoyAutoHeal -Apply -Trigger Scheduled' | Should -BeTrue

        $event = @(Get-DomovoyLedger | Where-Object { $_.event -eq 'watchdog.register' }) | Select-Object -Last 1
        $event | Should -Not -BeNullOrEmpty
        $event.dailyAt | Should -Be '21:30'
    }

    It 'unregister removes the task and journals the fact' {
        $null = Register-DomovoyWatchdog -Apply
        $undone = Unregister-DomovoyWatchdog -Apply
        $undone.Mode | Should -Be 'Apply'
        ($script:unregistered -contains '-TaskPath') | Should -BeTrue
        $event = @(Get-DomovoyLedger | Where-Object { $_.event -eq 'watchdog.unregister' }) | Select-Object -Last 1
        $event | Should -Not -BeNullOrEmpty
    }
}
