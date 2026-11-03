# Pester 5 evaluates -Skip at DISCOVERY, before any BeforeAll runs - the
# platform flag must live at the file top level, or every gate that reads
# it sees an undefined variable and the gate goes dead (v1.4.1, finding
# P1-13: the Windows-only blocks of these suites never executed in CI).
# NOTE: the variable must not be named *isWindows* - that name collides
# with the read-only automatic $IsWindows (names are case-insensitive).
$script:isWindowsPlatform = ($PSVersionTable.PSVersion.Major -lt 6) -or $IsWindows

# The admin flag must ALSO live at the file top level - the same Pester 5
# discovery rule as the platform flag above (v1.4.1, finding P1-13): the
# admin-gated tests of this suite never executed anywhere while the flag
# lived inside BeforeAll. Non-Windows platforms are non-admin and the
# skips engage.
$script:isAdmin = $false
try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object -TypeName Security.Principal.WindowsPrincipal -ArgumentList $identity
    $script:isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
catch {
    $script:isAdmin = $false
}

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $env:DOMOVOY_STORE = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("domovoy-v07-" + [guid]::NewGuid().ToString('N'))
    $env:DOMOVOY_FEATURES_DIR = Join-Path -Path $repoRoot -ChildPath 'config/features'
    Import-Module (Join-Path -Path $repoRoot -ChildPath 'src/Domovoy/Domovoy.psd1') -Force

    $script:manifestDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("domovoy-v07-manifests-" + [guid]::NewGuid().ToString('N'))
    New-Item -Path $script:manifestDir -ItemType Directory -Force | Out-Null

    $script:registryRef = 'https://learn.microsoft.com/windows/win32/sysinfo/registry'
}

AfterAll {
    Remove-Module -Name Domovoy -Force -ErrorAction SilentlyContinue
    if ($env:DOMOVOY_STORE -like "$([System.IO.Path]::GetTempPath())domovoy-v07-*") {
        Remove-Item -LiteralPath $env:DOMOVOY_STORE -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Registry.pol (PReg) format (catalog 62)' {
    It 'round-trips dword, qword, string, expandstring, delete markers and the default value name' {
        $entries = @(
            @{ KeyPath = 'SOFTWARE\Policies\Domovoy'; ValueName = 'Flag'; RegType = 'REG_DWORD'; Data = 0 }
            @{ KeyPath = 'SOFTWARE\Policies\Domovoy'; ValueName = 'Big'; RegType = 'REG_QWORD'; Data = [uint64]4294967296 }
            @{ KeyPath = 'SOFTWARE\Policies\Domovoy'; ValueName = 'Text'; RegType = 'REG_SZ'; Data = 'C:\Program Files\App' }
            @{ KeyPath = 'SOFTWARE\Policies\Domovoy'; ValueName = 'Path'; RegType = 'REG_EXPAND_SZ'; Data = '%ProgramFiles%\App' }
            @{ KeyPath = 'SOFTWARE\Policies\Domovoy'; ValueName = '**Del.Old'; RegType = 'REG_SZ'; Data = '' }
            @{ KeyPath = 'SOFTWARE\Policies\Domovoy'; ValueName = ''; RegType = 'REG_SZ'; Data = 'default-value' }
        )
        $bytes = InModuleScope Domovoy {
            param($Entries)
            ConvertTo-DomovoyRegistryPol -Entry $Entries
        } -Parameters @{ Entries = $entries }

        # 'PReg' + version 1.
        ($bytes[0..3] -join ',') | Should -Be '80,82,101,103'
        $bytes[4] | Should -Be 1

        $parsed = @(InModuleScope Domovoy {
            param($Bytes)
            Read-DomovoyRegistryPol -Bytes $Bytes
        } -Parameters @{ Bytes = $bytes })
        $parsed.Count | Should -Be 6
        $parsed[0].RegType | Should -Be 'REG_DWORD'
        $parsed[0].Data | Should -Be 0
        $parsed[1].Data | Should -Be ([uint64]4294967296)
        $parsed[2].Data | Should -Be 'C:\Program Files\App'
        $parsed[3].Data | Should -Be '%ProgramFiles%\App'
        $parsed[4].ValueName | Should -Be '**Del.Old'
        $parsed[5].ValueName | Should -Be ''
        $parsed[5].Data | Should -Be 'default-value'
    }

    It 'rejects a file with a bad signature' {
        $junk = [byte[]](1, 2, 3, 4, 5, 6, 7, 8, 9, 10)
        {
            InModuleScope Domovoy {
                param($Bytes)
                Read-DomovoyRegistryPol -Bytes $Bytes
            } -Parameters @{ Bytes = $junk }
        } | Should -Throw '*bad signature*'
    }
}

Describe 'network.proxy op (v0.7.0)' {
    BeforeEach {
        $script:proxyState = @{
            'ProxyEnable' = '<unset>'
            'ProxyServer' = '<unset>'
            'AutoConfigURL' = '<unset>'
            'ProxyOverride' = '<unset>'
        }
        # Capture the real cmdlets BEFORE mocking: a mock defined in module
        # session state intercepts the module-qualified name as well, so a
        # qualified call inside the mock body would recurse until the call
        # depth overflows. Invoking the captured CommandInfo bypasses name
        # resolution entirely (and keeps the fallback cross-platform).
        $realTestPath = Get-Command -Name Test-Path -CommandType Cmdlet -ErrorAction SilentlyContinue
        $realNewItem = Get-Command -Name New-Item -CommandType Cmdlet -ErrorAction SilentlyContinue
        InModuleScope Domovoy {
            param($State, $RealTestPath, $RealNewItem)

            $script:V07ProxyState = $State
            $script:V07RealTestPath = $RealTestPath
            $script:V07RealNewItem = $RealNewItem

            Mock Get-RegistryValueSafe {
                param($Path, $Name)
                $script:V07ProxyState[$Name]
            }
            Mock Test-Path {
                param($LiteralPath, $Path)
                $target = if ($LiteralPath) { $LiteralPath } else { $Path }
                if ($target -like 'HKCU:*') { return $true }
                if ($script:V07RealTestPath) { return & $script:V07RealTestPath @PSBoundParameters }
                return $true
            } -ParameterFilter { ($Path -like 'HK*:*') -or ($LiteralPath -like 'HK*:*') }
            Mock New-Item {
                param($Path)
                if ($Path -like 'HKCU:*') { return $null }
                if ($script:V07RealNewItem) { return & $script:V07RealNewItem @PSBoundParameters }
                return $null
            } -ParameterFilter { $Path -like 'HK*:*' }
            Mock New-ItemProperty {
                param($LiteralPath, $Name, $Value, $PropertyType, $Force)
                # Pester 5.7.1 copies the real cmdlet's parameter metadata onto
                # the mock; parameters declared as [String[]] arrive wrapped in
                # a one-element array even for scalar input (CI run 51). An
                # array key silently writes a shadow entry the assertions never
                # see - normalize to the plain scalar first.
                $valueName = [string](@($Name)[0])
                $script:V07ProxyState[$valueName] = [string](@($Value)[0])
                return $null
            }
            Mock Remove-ItemProperty {
                param($LiteralPath, $Name)
                # Remove-ItemProperty -Name is [String[]]: the scalar arrives
                # wrapped (run 51) - the undo's '<unset>' write landed on a
                # shadow array-keyed entry while the assertions read the
                # original string key and saw the pre-undo value.
                $valueName = [string](@($Name)[0])
                $script:V07ProxyState[$valueName] = '<unset>'
                return $null
            }
            Mock Test-DomovoyAdmin { return $true }
        } -Parameters @{ State = $script:proxyState; RealTestPath = $realTestPath; RealNewItem = $realNewItem }

        $script:proxyManifest = Join-Path -Path $script:manifestDir -ChildPath 'proxy-test.json'
        @{
            id = 'test.proxy.server'
            title = 'Test fixture: explicit proxy server'
            version = '1.0.0'
            category = 'network'
            risk = 'medium'
            description = 'Test fixture: sets an explicit WinINET proxy for the current user.'
            ops = @(@{ type = 'network.proxy'; mode = 'server'; proxyServer = 'proxy.local:3128'; bypassLocal = $true })
            undo = @{ mode = 'snapshot' }
            verify = @(@{ type = 'network.proxy'; proxyEnable = 1; proxyServer = 'proxy.local:3128'; autoConfigUrl = '<unset>' })
            references = @($script:registryRef)
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $script:proxyManifest -Encoding UTF8
    }

    It 'dry-run shows the WinINET plan and changes nothing' {
        $dry = Invoke-DomovoyFeature -ManifestFile $script:proxyManifest
        $dry.Mode | Should -Be 'DryRun'
        $row = @($dry.Plan | Where-Object { $_.Op -eq 'network.proxy' })
        $row.Count | Should -Be 1
        $row[0].Target | Should -Be 'WinINET (current user)'
        $row[0].Current | Should -Be 'enable=<unset>;server=<unset>;pac=<unset>'
        $row[0].New | Should -Be 'enable=1;server=proxy.local:3128'
        $script:proxyState['ProxyEnable'] | Should -Be '<unset>'
    }

    It 'apply sets the proxy values, the probe and the change report agree' -Skip:(-not $script:isAdmin) {
        $applied = Invoke-DomovoyFeature -ManifestFile $script:proxyManifest -Apply -SkipRestorePoint
        $applied.Mode | Should -Be 'Apply'
        $applied.Verification.AllPass | Should -BeTrue
        $script:proxyState['ProxyEnable'] | Should -Be '1'
        $script:proxyState['ProxyServer'] | Should -Be 'proxy.local:3128'
        $script:proxyState['ProxyOverride'] | Should -Be '<local>'

        $change = @($applied.Changes | Where-Object { $_.Probe -eq 'network.proxy' })
        $change.Count | Should -Be 1
        $change[0].Before | Should -Be 'enable=<unset>;server=<unset>;pac=<unset>'
        $change[0].After | Should -Be 'enable=1;server=proxy.local:3128;pac=<unset>'
        $change[0].Changed | Should -BeTrue
    }

    It 'undo removes what did not exist and restores what did' -Skip:(-not $script:isAdmin) {
        $null = Invoke-DomovoyFeature -ManifestFile $script:proxyManifest -Apply -SkipRestorePoint
        $null = Undo-DomovoyFeature -Id 'test.proxy.server' -Apply
        $script:proxyState['ProxyEnable'] | Should -Be '<unset>'
        $script:proxyState['ProxyServer'] | Should -Be '<unset>'
        $script:proxyState['ProxyOverride'] | Should -Be '<unset>'
    }

    It 'mode "off" disables the proxy without touching the server strings' -Skip:(-not $script:isAdmin) {
        $script:proxyState['ProxyEnable'] = '1'
        $script:proxyState['ProxyServer'] = 'old.proxy:80'
        $offManifest = Join-Path -Path $script:manifestDir -ChildPath 'proxy-off.json'
        @{
            id = 'test.proxy.off'
            title = 'Test fixture: proxy off'
            version = '1.0.0'
            category = 'network'
            risk = 'low'
            description = 'Test fixture: disables the WinINET proxy for the current user.'
            ops = @(@{ type = 'network.proxy'; mode = 'off' })
            undo = @{ mode = 'snapshot' }
            verify = @(@{ type = 'network.proxy'; proxyEnable = 0; proxyServer = 'old.proxy:80'; autoConfigUrl = '<unset>' })
            references = @($script:registryRef)
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $offManifest -Encoding UTF8

        $applied = Invoke-DomovoyFeature -ManifestFile $offManifest -Apply -SkipRestorePoint
        $applied.Verification.AllPass | Should -BeTrue
        $script:proxyState['ProxyEnable'] | Should -Be '0'
        $script:proxyState['ProxyServer'] | Should -Be 'old.proxy:80'
    }
}

Describe 'Theme switch (catalog 29)' {
    BeforeEach {
        $script:themeState = @{ Current = '1' }
        InModuleScope Domovoy {
            param($State)

            $script:V07ThemeState = $State

            Mock Get-RegistryValueSafe {
                param($Path, $Name)
                if ($Name -eq 'AppsUseLightTheme') { return $script:V07ThemeState.Current }
                return '<unset>'
            }
            Mock Invoke-DomovoyFeature {
                param($Id, $Apply)
                [pscustomobject]@{ Feature = $Id; Mode = 'Apply' }
            }
        } -Parameters @{ State = $script:themeState }
    }

    It 'dry-run resolves the toggle direction and calls nothing' {
        $dry = Switch-DomovoyTheme
        $dry.Mode | Should -Be 'DryRun'
        $dry.TargetTheme | Should -Be 'dark'
        $dry.CurrentAppsUseLightTheme | Should -Be '1'
        InModuleScope Domovoy { Assert-MockCalled Invoke-DomovoyFeature -Exactly 0 }
    }

    It 'a live dark theme toggles back to light' {
        $script:themeState.Current = '0'
        $dry = Switch-DomovoyTheme
        $dry.TargetTheme | Should -Be 'light'
    }

    It '-Theme forces the direction' {
        $dry = Switch-DomovoyTheme -Theme Light
        $dry.TargetTheme | Should -Be 'light'
        $script:themeState.Current = '0'
        $dry = Switch-DomovoyTheme -Theme Dark
        $dry.TargetTheme | Should -Be 'dark'
    }

    It 'apply drives the resolved theme manifest through the standard pipeline' -Skip:(-not $script:isAdmin) {
        $applied = Switch-DomovoyTheme -Apply
        $applied.Feature | Should -Be 'theme.dark'
        InModuleScope Domovoy {
            Assert-MockCalled Invoke-DomovoyFeature -Exactly 1 -ParameterFilter { $Id -eq 'theme.dark' -and $Apply }
        }
    }
}

Describe 'Network report (catalog 33)' {
    It 'reports adapters, dns and both proxy layers read-only' {
        $rows = @(InModuleScope Domovoy {
            Mock Get-NetAdapter {
                @(
                    [pscustomobject]@{ Name = 'Ethernet'; Status = 'Up'; InterfaceDescription = 'Ethernet Adapter'; MacAddress = 'AA-BB-CC-DD-EE-FF' }
                )
            }
            Mock Get-NetIPAddress {
                @(
                    [pscustomobject]@{ InterfaceAlias = 'Ethernet'; IPAddress = '192.168.1.10'; PrefixLength = 24 }
                )
            }
            Mock Get-DnsClientServerAddress {
                @(
                    [pscustomobject]@{ InterfaceAlias = 'Ethernet'; ServerAddresses = @('1.1.1.1', '1.0.0.1') }
                )
            }
            Mock Get-DnsClientGlobalSetting {
                [pscustomobject]@{ SuffixSearchList = 'corp.local' }
            }
            Mock Get-RegistryValueSafe {
                param($Path, $Name)
                if ($Name -eq 'ProxyEnable') { return '0' }
                return '<unset>'
            }
            Mock netsh {
                $global:LASTEXITCODE = 0
                @('', 'Direct access (no proxy server).', '')
            }

            $script:V07ReportRows = @(Get-DomovoyNetworkReport)
            $script:V07ReportRows
        })

        ($rows | Where-Object { $_.Section -eq 'adapter' }).Count | Should -Be 1
        ($rows | Where-Object { $_.Section -eq 'ip' })[0].Value | Should -Be '192.168.1.10 (prefix 24)'
        ($rows | Where-Object { $_.Section -eq 'dns' })[0].Value | Should -Be '1.1.1.1, 1.0.0.1'
        ($rows | Where-Object { $_.Section -eq 'dns-global' })[0].Value | Should -Be 'corp.local'
        ($rows | Where-Object { $_.Section -eq 'proxy-wininet' }).Count | Should -Be 4
        ($rows | Where-Object { $_.Section -eq 'proxy-winhttp' }).Count | Should -Be 1
    }
}

Describe 'Network state export/restore (catalog 35)' {
    BeforeEach {
        $script:netState = @{
            DnsTargets = @('Ethernet')
            Servers = @('1.1.1.1', '1.0.0.1')
            ProxyEnable = '1'
            ProxyServer = 'proxy.local:3128'
            ProxyOverride = '<local>'
        }
        InModuleScope Domovoy {
            param($State)

            $script:V07NetState = $State

            Mock Get-DomovoyDnsTargets {
                param($InterfaceAlias)
                @($script:V07NetState.DnsTargets)
            }
            Mock Get-DnsClientServerAddress {
                [pscustomobject]@{ InterfaceAlias = 'Ethernet'; ServerAddresses = @($script:V07NetState.Servers) }
            }
            Mock Get-RegistryValueSafe {
                param($Path, $Name)
                switch ($Name) {
                    'ProxyEnable' { return $script:V07NetState.ProxyEnable }
                    'ProxyServer' { return $script:V07NetState.ProxyServer }
                    'ProxyOverride' { return $script:V07NetState.ProxyOverride }
                    default { return '<unset>' }
                }
            }
        } -Parameters @{ State = $script:netState }
    }

    It 'exports dns and proxy to a JSON file, read-only' {
        $result = Export-DomovoyNetworkState
        Test-Path -LiteralPath $result.Path | Should -BeTrue
        $state = Get-Content -LiteralPath $result.Path -Raw -Encoding UTF8 | ConvertFrom-Json
        $state.kind | Should -Be 'domovoy-network-state'
        @($state.dns).Count | Should -Be 1
        @($state.dns[0].servers) | Should -Be @('1.1.1.1', '1.0.0.1')
        $state.proxy.proxyEnable | Should -Be '1'
        $state.proxy.proxyServer | Should -Be 'proxy.local:3128'
        $result.Adapters | Should -Be 1
    }

    It 'restore dry-run builds a generated manifest; adapters without captured dns are skipped' {
        $statePath = Join-Path -Path (Get-PSDrive TestDrive).Root -ChildPath 'state.json'
        @{
            schemaVersion = 1
            kind = 'domovoy-network-state'
            exportedAt = '2026-11-02T00:00:00.000Z'
            dns = @(
                @{ interfaceAlias = 'Ethernet'; servers = @('1.1.1.1') }
                @{ interfaceAlias = 'Old'; servers = @() }
            )
            proxy = @{ proxyEnable = '0'; proxyServer = '<unset>'; autoConfigUrl = '<unset>'; proxyOverride = '<unset>' }
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $statePath -Encoding UTF8

        $dry = Restore-DomovoyNetworkState -Path $statePath
        $dry.Mode | Should -Be 'DryRun'
        $dry.ManifestFile | Should -BeLike '*generated*network.state.restore.json'
        ($dry.Skipped | Where-Object { $_ -like 'Old:*' }).Count | Should -Be 1

        $manifest = Get-Content -LiteralPath $dry.ManifestFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $manifest.id | Should -Be 'network.state.restore'
        @($manifest.ops).Count | Should -Be 2
        $manifest.ops[0].type | Should -Be 'network.dns'
        @($manifest.ops[0].servers) | Should -Be @('1.1.1.1')
        $manifest.ops[1].type | Should -Be 'network.proxy'
        $manifest.ops[1].mode | Should -Be 'off'
        # The probe pins the full captured triple.
        $manifest.verify[1].proxyServer | Should -Be '<unset>'
        $manifest.verify[1].autoConfigUrl | Should -Be '<unset>'
    }

    It 'restore apply runs the full pipeline: execute, probes, journal' -Skip:(-not $script:isAdmin) {
        $realTestPath = Get-Command -Name Test-Path -CommandType Cmdlet -ErrorAction SilentlyContinue
        $realNewItem = Get-Command -Name New-Item -CommandType Cmdlet -ErrorAction SilentlyContinue
        InModuleScope Domovoy {
            param($RealTestPath, $RealNewItem)
            $script:V07RealTestPath2 = $RealTestPath
            $script:V07RealNewItem2 = $RealNewItem
            Mock Test-Path {
                param($LiteralPath, $Path)
                $target = if ($LiteralPath) { $LiteralPath } else { $Path }
                if ($target -like 'HKCU:*') { return $true }
                if ($script:V07RealTestPath2) { return & $script:V07RealTestPath2 @PSBoundParameters }
                return $true
            } -ParameterFilter { ($Path -like 'HK*:*') -or ($LiteralPath -like 'HK*:*') }
            Mock New-Item {
                param($Path)
                if ($Path -like 'HKCU:*') { return $null }
                if ($script:V07RealNewItem2) { return & $script:V07RealNewItem2 @PSBoundParameters }
                return $null
            } -ParameterFilter { $Path -like 'HK*:*' }
            Mock New-ItemProperty {
                param($LiteralPath, $Name, $Value, $PropertyType, $Force)
                $script:V07NetState.ProxyEnable = [string]$Value
                return $null
            }
            Mock Set-DnsClientServerAddress {
                param($InterfaceAlias, $ServerAddresses, $ResetServerAddresses)
                $script:V07NetState.Servers = @($ServerAddresses)
                return $null
            }
            Mock Test-DomovoyAdmin { return $true }
        }

        $statePath = Join-Path -Path (Get-PSDrive TestDrive).Root -ChildPath 'state-apply.json'
        @{
            schemaVersion = 1
            kind = 'domovoy-network-state'
            exportedAt = '2026-11-02T00:00:00.000Z'
            dns = @(
                @{ interfaceAlias = 'Ethernet'; servers = @('9.9.9.9') }
            )
            proxy = @{ proxyEnable = '0'; proxyServer = '<unset>'; autoConfigUrl = '<unset>'; proxyOverride = '<unset>' }
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $statePath -Encoding UTF8

        # The mock reads live state from the same hashtable the export
        # mocked earlier; align it with what this state file carries so
        # the verification probes check the state this restore produces.
        $script:netState.ProxyServer = '<unset>'
        $script:netState.ProxyOverride = '<unset>'
        $applied = Restore-DomovoyNetworkState -Path $statePath -Apply -SkipRestorePoint
        $applied.Mode | Should -Be 'Apply'
        $applied.Verification.AllPass | Should -BeTrue
        $script:netState.Servers | Should -Be @('9.9.9.9')
        $script:netState.ProxyEnable | Should -Be '0'

        $events = @(Get-DomovoyLedger -FeatureId 'network.state.restore' -Event 'feature.apply')
        $events.Count | Should -Be 1
    }

    It 'a never-configured proxy is honestly skipped, not recreated as disabled' {
        $statePath = Join-Path -Path (Get-PSDrive TestDrive).Root -ChildPath 'state-unset.json'
        @{
            schemaVersion = 1
            kind = 'domovoy-network-state'
            exportedAt = '2026-11-02T00:00:00.000Z'
            dns = @(
                @{ interfaceAlias = 'Ethernet'; servers = @('1.1.1.1') }
            )
            proxy = @{ proxyEnable = '<unset>'; proxyServer = '<unset>'; autoConfigUrl = '<unset>'; proxyOverride = '<unset>' }
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $statePath -Encoding UTF8

        $dry = Restore-DomovoyNetworkState -Path $statePath
        ($dry.Skipped | Where-Object { $_ -like 'proxy:*' }).Count | Should -Be 1
        $manifest = Get-Content -LiteralPath $dry.ManifestFile -Raw -Encoding UTF8 | ConvertFrom-Json
        @($manifest.ops | Where-Object { $_.type -eq 'network.proxy' }).Count | Should -Be 0
    }
}

Describe 'Policy export (catalog 62)' {
    BeforeEach {
        $script:policyFeatures = Join-Path -Path (Get-PSDrive TestDrive).Root -ChildPath 'policy-features'
        New-Item -Path $script:policyFeatures -ItemType Directory -Force | Out-Null
        $env:DOMOVOY_FEATURES_DIR_BACKUP = $env:DOMOVOY_FEATURES_DIR
        $env:DOMOVOY_FEATURES_DIR = $script:policyFeatures

        # Five manifests: machine dword, user string, a delete, a conflicting
        # later apply for the same machine value, and one without verification.
        @{
            id = 'v07.export.machine'
            title = 'Machine value'
            version = '1.0.0'
            category = 'privacy'
            risk = 'low'
            description = 'Test fixture: one machine dword.'
            ops = @(@{ type = 'registry.set'; path = 'HKLM:\SOFTWARE\Policies\DomovoyExport'; name = 'Value'; value = 0; valueType = 'DWord' })
            undo = @{ mode = 'snapshot' }
            verify = @(@{ type = 'registry.set'; path = 'HKLM:\SOFTWARE\Policies\DomovoyExport'; name = 'Value'; value = 0 })
            references = @($script:registryRef)
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $script:policyFeatures 'machine.json') -Encoding UTF8

        @{
            id = 'v07.export.user'
            title = 'User value'
            version = '1.0.0'
            category = 'privacy'
            risk = 'low'
            description = 'Test fixture: one user string.'
            ops = @(@{ type = 'registry.set'; path = 'HKCU:\Software\DomovoyExport'; name = 'Label'; value = 'hello world'; valueType = 'String' })
            undo = @{ mode = 'snapshot' }
            verify = @(@{ type = 'registry.set'; path = 'HKCU:\Software\DomovoyExport'; name = 'Label'; value = 'hello world' })
            references = @($script:registryRef)
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $script:policyFeatures 'user.json') -Encoding UTF8

        @{
            id = 'v07.export.delete'
            title = 'Delete a legacy value'
            version = '1.0.0'
            category = 'privacy'
            risk = 'low'
            description = 'Test fixture: one registry delete.'
            ops = @(@{ type = 'registry.delete'; path = 'HKLM:\SOFTWARE\Policies\DomovoyExport'; name = 'Legacy' })
            undo = @{ mode = 'snapshot' }
            verify = @(@{ type = 'registry.absent'; path = 'HKLM:\SOFTWARE\Policies\DomovoyExport'; name = 'Legacy' })
            references = @($script:registryRef)
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $script:policyFeatures 'delete.json') -Encoding UTF8

        @{
            id = 'v07.export.conflict'
            title = 'Conflicting later value'
            version = '1.0.0'
            category = 'privacy'
            risk = 'low'
            description = 'Test fixture: the same machine value with a different data.'
            ops = @(@{ type = 'registry.set'; path = 'HKLM:\SOFTWARE\Policies\DomovoyExport'; name = 'Value'; value = 5; valueType = 'DWord' })
            undo = @{ mode = 'snapshot' }
            verify = @(@{ type = 'registry.set'; path = 'HKLM:\SOFTWARE\Policies\DomovoyExport'; name = 'Value'; value = 5 })
            references = @($script:registryRef)
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $script:policyFeatures 'conflict.json') -Encoding UTF8

        @{
            id = 'v07.export.unverified'
            title = 'Unverified feature'
            version = '1.0.0'
            category = 'privacy'
            risk = 'low'
            description = 'Test fixture: an apply without verification results.'
            ops = @(@{ type = 'registry.set'; path = 'HKLM:\SOFTWARE\Policies\DomovoyExport'; name = 'Unverified'; value = 1; valueType = 'DWord' })
            undo = @{ mode = 'snapshot' }
            verify = @(@{ type = 'registry.set'; path = 'HKLM:\SOFTWARE\Policies\DomovoyExport'; name = 'Unverified'; value = 1 })
            references = @($script:registryRef)
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $script:policyFeatures 'unverified.json') -Encoding UTF8

        $null = Initialize-Domovoy
        $ledger = Join-Path -Path $env:DOMOVOY_STORE -ChildPath 'ledger.jsonl'
        @(
            @{ timestamp = '2026-11-02T10:00:00.000Z'; event = 'feature.apply'; featureId = 'v07.export.machine'; featureVersion = '1.0.0'; featureSource = (Join-Path $script:policyFeatures 'machine.json'); snapshot = @(); verification = @{ AllPass = $true; Results = @() } }
            @{ timestamp = '2026-11-02T10:01:00.000Z'; event = 'feature.apply'; featureId = 'v07.export.user'; featureVersion = '1.0.0'; featureSource = (Join-Path $script:policyFeatures 'user.json'); snapshot = @(); verification = @{ AllPass = $true; Results = @() } }
            @{ timestamp = '2026-11-02T10:02:00.000Z'; event = 'feature.apply'; featureId = 'v07.export.delete'; featureVersion = '1.0.0'; featureSource = (Join-Path $script:policyFeatures 'delete.json'); snapshot = @(); verification = @{ AllPass = $true; Results = @() } }
            @{ timestamp = '2026-11-02T10:03:00.000Z'; event = 'feature.apply'; featureId = 'v07.export.unverified'; featureVersion = '1.0.0'; featureSource = (Join-Path $script:policyFeatures 'unverified.json'); snapshot = @() }
            @{ timestamp = '2026-11-02T10:04:00.000Z'; event = 'feature.apply'; featureId = 'v07.export.conflict'; featureVersion = '1.0.0'; featureSource = (Join-Path $script:policyFeatures 'conflict.json'); snapshot = @(); verification = @{ AllPass = $true; Results = @() } }
        ) | ForEach-Object { $_ | ConvertTo-Json -Depth 8 -Compress } |
            Set-Content -LiteralPath $ledger -Encoding UTF8
    }

    AfterEach {
        $env:DOMOVOY_FEATURES_DIR = $env:DOMOVOY_FEATURES_DIR_BACKUP
        Remove-Item Env:DOMOVOY_FEATURES_DIR_BACKUP -ErrorAction SilentlyContinue
    }

    It 'exports verified registry-backed features into a gpedit-loadable bundle' {
        $out = Join-Path -Path (Get-PSDrive TestDrive).Root -ChildPath 'export'
        $result = Export-DomovoyPolicy -OutputDir $out -Force

        $result.SelfCheck | Should -BeLike 'pass*'
        # Value (deduped: conflict feature won) + **Del.Legacy; the
        # unverified feature contributes nothing.
        $result.MachineEntries | Should -Be 2
        $result.UserEntries | Should -Be 1
        $result.AdmxPolicies | Should -Be 4
        Test-Path -LiteralPath $result.Admx | Should -BeTrue
        Test-Path -LiteralPath $result.Adml | Should -BeTrue
        Test-Path -LiteralPath $result.MachinePol | Should -BeTrue
        Test-Path -LiteralPath $result.UserPol | Should -BeTrue
        Test-Path -LiteralPath $result.MappingCsv | Should -BeTrue
        Test-Path -LiteralPath $result.Readme | Should -BeTrue
        ($result.Skipped | Where-Object { $_ -like 'v07.export.unverified*' }).Count | Should -Be 1
        ($result.Conflicts | Where-Object { $_ -like '*v07.export.conflict'' overwrites *' }).Count | Should -Be 1
    }

    It 'the machine pol parses back; the newer feature wins the shared value' {
        $out = Join-Path -Path (Get-PSDrive TestDrive).Root -ChildPath 'export2'
        $null = Export-DomovoyPolicy -OutputDir $out -Force
        $bytes = [System.IO.File]::ReadAllBytes((Join-Path -Path $out -ChildPath 'Machine-Registry.pol'))
        $entries = @(InModuleScope Domovoy {
            param($Bytes)
            Read-DomovoyRegistryPol -Bytes $Bytes
        } -Parameters @{ Bytes = $bytes })

        ($entries | Where-Object { $_.ValueName -eq 'Value' }).Count | Should -Be 1
        ($entries | Where-Object { $_.ValueName -eq 'Value' }).Data | Should -Be 5
        ($entries | Where-Object { $_.ValueName -eq '**Del.Legacy' }).Count | Should -Be 1

        $userBytes = [System.IO.File]::ReadAllBytes((Join-Path -Path $out -ChildPath 'User-Registry.pol'))
        $userEntries = @(InModuleScope Domovoy {
            param($Bytes)
            Read-DomovoyRegistryPol -Bytes $Bytes
        } -Parameters @{ Bytes = $userBytes })
        $userEntries[0].ValueName | Should -Be 'Label'
        $userEntries[0].Data | Should -Be 'hello world'
    }

    It 'the admx declares one policy per feature class with pinned elements' {
        $out = Join-Path -Path (Get-PSDrive TestDrive).Root -ChildPath 'export3'
        $null = Export-DomovoyPolicy -OutputDir $out -Force

        $admx = Get-Content -LiteralPath (Join-Path -Path $out -ChildPath 'Domovoy.admx') -Raw -Encoding UTF8
        { [xml]$admx } | Should -Not -Throw
        $admx | Should -Match '<category name="Domovoy"'
        $admx | Should -Match '<decimal id="V1" valueName="Value"'
        $admx | Should -Match '<text id="V1" valueName="Label"'
        $admx | Should -Match '<delete id="V1" valueName="Legacy"'

        $adml = Get-Content -LiteralPath (Join-Path -Path $out -ChildPath 'en-US\Domovoy.adml') -Raw -Encoding UTF8
        { [xml]$adml } | Should -Not -Throw
        $adml | Should -Match 'Domovoy tweaks'
    }
}

Describe 'GUI (Show-Domovoy)' {
    It 'builds the whole window in preview mode: catalog in, journal status on' -Skip:(-not $script:isWindowsPlatform) {
        $form = Show-Domovoy -Preview
        try {
            $form | Should -BeOfType [System.Windows.Forms.Form]
            $form.Tag.Output.Text | Should -Match 'Domovoy GUI'
            $form.Tag.List.Columns.Count | Should -Be 4
            # The catalog grows with every wave: the window carries
            # exactly the live manifest count, never a frozen number
            # (the frozen 31 broke the moment the catalog hit 58 -
            # first fallout of the v1.4.1 unmasking).
            $form.Tag.List.Items.Count | Should -Be @((Get-DomovoyFeature)).Count
        }
        finally {
            $form.Dispose()
        }
    }

    It 'is exported as a public command' {
        Get-Command Show-Domovoy | Should -Not -BeNullOrEmpty
        (Get-Command Show-Domovoy).Parameters.Keys | Should -Contain 'Preview'
    }

    It 'GUI click-handler surface resolves the private string table through the module-bound bridge (v1.5.4 portable-exe regression)' -Skip:(-not $script:isWindowsPlatform) {
        # The v1.5.3 portable exe crashed on EVERY click: the handlers run
        # inside .GetNewClosure() scopes whose command lookup reaches only
        # the global session state - the private Get-DomovoyStrings was not
        # visible there (Button.OnMouseUp -> CommandNotFoundException, and
        # CI stayed green because -Preview builds the window but never
        # clicks). The probe in Tag is bound exactly like the handlers
        # (.GetNewClosure over the bridge variable) and is invoked here
        # headlessly. Runs 77-79: PerformClick never delivers under
        # headless Pester on windows-latest (no handle arrangement lands
        # the event), so the regression is pinned to the session-state
        # surface itself - the thing that actually crashed - not to the
        # runner's message loop.
        $expectedSelect = InModuleScope Domovoy { (Get-DomovoyStrings).selectFirst }
        $form = Show-Domovoy -Preview
        try {
            $buttons = $form.Tag.Buttons
            $buttons.DryRun | Should -BeOfType [System.Windows.Forms.Button]
            $buttons.Refresh | Should -BeOfType [System.Windows.Forms.Button]
            $buttons.Changes | Should -BeOfType [System.Windows.Forms.Button]

            # The exact surface the crash lived on: a handler-style closure
            # resolving the private table through the bridge.
            & $form.Tag.Probe | Should -Be $expectedSelect

            # Still live after a language switch, through the same bridge
            # (the language-switch button updates its own label this way).
            Set-DomovoyLanguage -Language ru | Out-Null
            try {
                $ruSelect = InModuleScope Domovoy { (Get-DomovoyStrings).selectFirst }
                & $form.Tag.Probe | Should -Be $ruSelect
            }
            finally {
                Set-DomovoyLanguage -Language en | Out-Null
            }
        }
        finally {
            $form.Dispose()
        }
    }

    It 'runs a catalog action through the background worker to done (v1.6.0 async surface)' -Skip:(-not $script:isWindowsPlatform) {
        # v1.6.0: actions leave the UI thread. The handler prints the CLI
        # line synchronously, flips State.busy, the worker executes the
        # exact command in a fresh runspace, and Drain (the timer's body)
        # marshals the output back and re-enables the buttons. The dry-run
        # is read-only, so the test is safe to run against the test store.
        $form = Show-Domovoy -Preview
        try {
            $tag = $form.Tag
            $tag.State.busy | Should -BeFalse

            # Guard path without a selection stays synchronous and never
            # touches the worker.
            & $tag.Handlers.DryRun
            $expectedSelect = InModuleScope Domovoy { (Get-DomovoyStrings).selectFirst }
            $tag.Output.Text | Should -Match ([regex]::Escape($expectedSelect))
            $tag.State.busy | Should -BeFalse

            # Select the first catalog row and dry-run it. The preview
            # form is headless, so force the native handles first:
            # ListView.SelectedItems reports state only through one (the
            # same headless-CI lesson as the v1.5.4 PerformClick hunt,
            # run 77-79). Selection is asserted so a future WinForms
            # change cannot silently degrade back to the guard path.
            $null = $form.Handle
            $null = $tag.List.Handle
            $tag.List.Items[0].Selected = $true
            $tag.List.SelectedItems.Count | Should -Be 1
            & $tag.Handlers.DryRun
            $tag.State.busy | Should -BeTrue
            $tag.Output.Text | Should -Match 'CLI: Invoke-DomovoyFeature'
            $tag.Buttons.DryRun.Enabled | Should -BeFalse

            # Drain until the worker reports done (max ~10s of wall time).
            $maxDrains = 200
            while ($tag.State.busy -and $maxDrains -gt 0) {
                & $tag.Drain
                if ($tag.State.busy) { Start-Sleep -Milliseconds 50 }
                $maxDrains--
            }
            $tag.State.busy | Should -BeFalse
            $tag.State.worker | Should -BeNullOrEmpty
            $tag.Buttons.DryRun.Enabled | Should -BeTrue
            $tag.Status.Text | Should -Not -BeNullOrEmpty
        }
        finally {
            $form.Dispose()
        }
    }

    It 'the catalog filter narrows the list live (v1.6.0 search)' -Skip:(-not $script:isWindowsPlatform) {
        $form = Show-Domovoy -Preview
        try {
            $tag = $form.Tag
            $all = $tag.List.Items.Count
            $all | Should -BeGreaterThan 0

            $tag.Search.Text = 'zzz-no-such-feature-zzz'
            $tag.List.Items.Count | Should -Be 0

            $tag.Search.Text = ''
            $tag.List.Items.Count | Should -Be $all
        }
        finally {
            $form.Dispose()
        }
    }
}
