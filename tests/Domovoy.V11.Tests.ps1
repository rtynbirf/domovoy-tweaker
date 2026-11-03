# Domovoy v1.1.0 tests: the second service wave, the second UWP wave, the
# proxy-off profile, the task-state export, winget hints in undo, the
# watchdog cleanup report, the thumbnail-cache cleanup target, the LSA
# audit and the batch policy export for profiles.
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
    $env:DOMOVOY_STORE = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("domovoy-v11-" + [guid]::NewGuid().ToString('N'))
    $env:DOMOVOY_FEATURES_DIR = Join-Path -Path $repoRoot -ChildPath 'config/features'
    Import-Module (Join-Path -Path $repoRoot -ChildPath 'src/Domovoy/Domovoy.psd1') -Force

    $script:manifestDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("domovoy-v11-manifests-" + [guid]::NewGuid().ToString('N'))
    New-Item -Path $script:manifestDir -ItemType Directory -Force | Out-Null

    $script:registryRef = 'https://learn.microsoft.com/windows/win32/sysinfo/registry'
}

AfterAll {
    Remove-Module -Name Domovoy -Force -ErrorAction SilentlyContinue
    if ($env:DOMOVOY_STORE -like "$([System.IO.Path]::GetTempPath())domovoy-v11-*") {
        Remove-Item -LiteralPath $env:DOMOVOY_STORE -Recurse -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath $script:manifestDir -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Second service wave (catalog 65)' {
    It 'dry-run builds a plan for each service without touching anything' {
        InModuleScope Domovoy {
            Mock Get-Service {
                param($Name, $ErrorAction)
                [pscustomobject]@{ Name = $Name; Status = 'Running'; StartType = 'Automatic' }
            }
            Mock Set-Service { }
            Mock Test-DomovoyAdmin { return $true }
        }
        foreach ($id in @('services.fax.disabled', 'services.retaildemo.disabled', 'services.wmpnetworksvc.disabled')) {
            $dry = Invoke-DomovoyFeature -Id $id
            $dry.Mode | Should -Be 'DryRun'
            $dry.Plan[0].Op | Should -Be 'service.startup'
        }
    }

    It 'apply disables and undo restores the previous startup type (mocked pipeline)' {
        InModuleScope Domovoy {
            $script:V11Svc = @{ StartType = 'Automatic'; Status = 'Running' }
            Mock Get-Service {
                param($Name, $ErrorAction)
                [pscustomobject]@{ Name = $Name; Status = $script:V11Svc.Status; StartType = $script:V11Svc.StartType }
            }
            Mock Set-Service { param($Name, $StartupType) $script:V11Svc.StartType = $StartupType }
            Mock Stop-Service { param($Name, $Force) $script:V11Svc.Status = 'Stopped' }
            Mock Start-Service { param($Name, $ErrorAction) $script:V11Svc.Status = 'Running' }
            Mock Test-DomovoyAdmin { return $true }
        }
        $applied = Invoke-DomovoyFeature -Id services.fax.disabled -Apply -SkipRestorePoint
        $applied.Mode | Should -Be 'Apply'
        $applied.Verification.AllPass | Should -BeTrue
        InModuleScope Domovoy {
            Assert-MockCalled Set-Service -Exactly 1 -ParameterFilter { $StartupType -eq 'Disabled' }
        }

        $undo = Undo-DomovoyFeature -Id services.fax.disabled -Apply
        $undo.Mode | Should -Be 'Undo'
        InModuleScope Domovoy {
            # The undo restores the exact previous startup type; the
            # service.startup snapshot records the type only, so nothing is
            # restarted behind the user's back.
            Assert-MockCalled Set-Service -Exactly 1 -ParameterFilter { $StartupType -eq 'Automatic' }
        }
    }
}

Describe 'Second UWP wave (catalog 76)' {
    BeforeEach {
        InModuleScope Domovoy {
            $script:V11Packages = @{}
            Mock Get-AppxPackage {
                param($Name)
                if ($Name -and $script:V11Packages.ContainsKey($Name) -and $script:V11Packages[$Name]) {
                    return [pscustomobject]@{ Name = $Name; PackageFullName = "$Name-full" }
                }
                return $null
            }
            Mock Remove-AppxPackage { $script:V11Packages = @{} }
            Mock Remove-AppxProvisionedPackage { }
            Mock Test-DomovoyAdmin { return $true }
        }
    }

    It 'dry-run builds a plan for each package without touching anything' {
        foreach ($id in @('packages.news.removed', 'packages.feedbackhub.removed', 'packages.solitairecollection.removed')) {
            $dry = Invoke-DomovoyFeature -Id $id
            $dry.Mode | Should -Be 'DryRun'
            $dry.Plan[0].Op | Should -Be 'appx.remove'
        }
    }

    It 'apply removes the package; the probe answers honestly' {
        InModuleScope Domovoy { $script:V11Packages['Microsoft.BingNews'] = $true }
        $applied = Invoke-DomovoyFeature -Id packages.news.removed -Apply -SkipRestorePoint
        $applied.Mode | Should -Be 'Apply'
        $applied.Verification.AllPass | Should -BeTrue
    }
}

Describe 'Proxy off profile (catalog 85)' {
    It 'apply turns the proxy off, keeps the server values, undo restores the triple' {
        $realTestPath = Get-Command -Name Test-Path -CommandType Cmdlet -ErrorAction SilentlyContinue
        $realNewItem = Get-Command -Name New-Item -CommandType Cmdlet -ErrorAction SilentlyContinue
        InModuleScope Domovoy {
            param($RealTestPath, $RealNewItem)
            $script:V11RealTestPath = $RealTestPath
            $script:V11RealNewItem = $RealNewItem
            # The exact documented triple; ProxyServer stays in place on
            # mode=off by contract, so the probe pins only ProxyEnable.
            $script:V11Proxy = @{
                ProxyEnable = '1'
                ProxyServer = 'proxy.local:3128'
                AutoConfigURL = '<unset>'
                ProxyOverride = '<unset>'
            }
            Mock Get-RegistryValueSafe {
                param($Path, $Name)
                return [string]$script:V11Proxy[$Name]
            }
            Mock Test-Path {
                param($LiteralPath, $Path)
                $target = if ($LiteralPath) { $LiteralPath } else { $Path }
                if ($target -like 'HKCU:*') { return $true }
                if ($script:V11RealTestPath) { return & $script:V11RealTestPath @PSBoundParameters }
                return $true
            } -ParameterFilter { ($Path -like 'HK*:*') -or ($LiteralPath -like 'HK*:*') }
            Mock New-Item {
                param($Path)
                if ($Path -like 'HKCU:*') { return $null }
                if ($script:V11RealNewItem) { return & $script:V11RealNewItem @PSBoundParameters }
                return $null
            } -ParameterFilter { $Path -like 'HK*:*' }
            Mock New-ItemProperty {
                param($LiteralPath, $Name, $Value, $PropertyType, $Force)
                if ($Name -eq 'ProxyEnable') { $script:V11Proxy.ProxyEnable = [string]$Value }
                if ($Name -eq 'ProxyServer') { $script:V11Proxy.ProxyServer = [string]$Value }
                if ($Name -eq 'AutoConfigURL') { $script:V11Proxy.AutoConfigURL = [string]$Value }
                return $null
            }
            Mock Remove-ItemProperty {
                param($LiteralPath, $Name)
                # Remove-ItemProperty -Name is [String[]] and Pester copies the
                # cmdlet's parameter metadata onto the mock: the scalar arrives
                # wrapped (CI run 51) - normalize before using it as a key.
                $valueName = [string](@($Name)[0])
                $script:V11Proxy[$valueName] = '<unset>'
                return $null
            }
            Mock Test-DomovoyAdmin { return $true }
        } -Parameters @{ RealTestPath = $realTestPath; RealNewItem = $realNewItem }

        $applied = Invoke-DomovoyFeature -Id network.proxy.off -Apply -SkipRestorePoint
        $applied.Mode | Should -Be 'Apply'
        $applied.Verification.AllPass | Should -BeTrue

        # mode=off contract: ProxyEnable is 0, the server value is kept.
        $state = InModuleScope Domovoy { $script:V11Proxy }
        $state.ProxyEnable | Should -Be '0'
        $state.ProxyServer | Should -Be 'proxy.local:3128'

        $undo = Undo-DomovoyFeature -Id network.proxy.off -Apply
        $undo.Mode | Should -Be 'Undo'
        $restored = InModuleScope Domovoy { $script:V11Proxy }
        $restored.ProxyEnable | Should -Be '1'
        $restored.ProxyServer | Should -Be 'proxy.local:3128'
    }
}

Describe 'Task state export (catalog 66)' {
    It 'exports the task table read-only as JSON' {
        InModuleScope Domovoy {
            Mock Get-ScheduledTask {
                @(
                    [pscustomobject]@{ TaskPath = '\Microsoft\Windows\'; TaskName = 'A'; State = 'Ready' }
                    [pscustomobject]@{ TaskPath = '\Domovoy\'; TaskName = 'DriftWatchdog'; State = 'Ready' }
                )
            }
        }
        $out = Join-Path -Path (Get-PSDrive TestDrive).Root -ChildPath 'tasks.json'
        $result = Backup-DomovoyTaskState -OutputPath $out
        $result.Tasks | Should -Be 2
        Test-Path -LiteralPath $out | Should -BeTrue
        $payload = Get-Content -LiteralPath $out -Raw | ConvertFrom-Json
        $payload.kind | Should -Be 'domovoy-task-state'
        $payload.count | Should -Be 2
        $payload.tasks[0].TaskName | Should -Be 'DriftWatchdog'
    }
}

Describe 'Winget hints in undo (catalog 75)' {
    It 'maps known packages and stays honest about unknown ones' {
        $hint = InModuleScope Domovoy { Get-DomovoyWingetHint -PackageName 'Microsoft.BingNews' }
        $hint | Should -Be 'Microsoft.BingNews'
        $none = InModuleScope Domovoy { Get-DomovoyWingetHint -PackageName 'Some.Random.Package' }
        $none | Should -BeNullOrEmpty
    }

    It 'the undo result carries the machine-readable hint when files are gone' {
        InModuleScope Domovoy {
            $script:V11Packages = @{ 'Microsoft.BingNews' = $true }
            Mock Get-AppxPackage {
                param($Name)
                if ($Name -and $script:V11Packages.ContainsKey($Name) -and $script:V11Packages[$Name]) {
                    # No InstallLocation property: the files are not on disk.
                    return [pscustomobject]@{ Name = $Name; PackageFullName = "$Name-full" }
                }
                return $null
            }
            Mock Remove-AppxPackage { $script:V11Packages = @{} }
            Mock Remove-AppxProvisionedPackage { }
            Mock Add-AppxPackage { }
            Mock Test-DomovoyAdmin { return $true }
        }
        $null = Invoke-DomovoyFeature -Id packages.news.removed -Apply -SkipRestorePoint
        $undo = Undo-DomovoyFeature -Id packages.news.removed -Apply
        $undo.Mode | Should -Be 'Undo'
        @($undo.WingetHints).Count | Should -Be 1
        $undo.WingetHints[0].Package | Should -Be 'Microsoft.BingNews'
        $undo.WingetHints[0].WingetId | Should -Be 'Microsoft.BingNews'
    }
}

Describe 'Cleanup thumb cache (catalog 89)' {
    It 'dry-run measures the thumbcache directory honestly' -Skip:(-not $script:isWindowsPlatform) {
        $dry = Invoke-DomovoyCleanup -Target ThumbCache
        $dry.Mode | Should -Be 'DryRun'
        $dry.Target | Should -Be 'ThumbCache'
        ([string]$dry.Paths[0]).EndsWith('Explorer') | Should -BeTrue
        $dry.Files | Should -BeGreaterOrEqual 0
    }

    It 'temp target keeps its documented shape' {
        $dry = Invoke-DomovoyCleanup -Target Temp
        $dry.Mode | Should -Be 'DryRun'
        $dry.Target | Should -Be 'Temp'
    }
}

Describe 'Watchdog cleanup report (catalog 87)' {
    It 'the dry-run shows whether the cleanup report is enabled' {
        $off = Register-DomovoyWatchdog
        $off.CleanupReport | Should -BeFalse
        $on = Register-DomovoyWatchdog -IncludeCleanupReport
        $on.CleanupReport | Should -BeTrue
    }

    It 'the generated runner appends the measured dry-run report' -Skip:(-not $script:isAdmin) {
        $result = Register-DomovoyWatchdog -IncludeCleanupReport -Apply
        $runner = Get-Content -LiteralPath $result.RunnerScript -Raw
        $runner | Should -BeLike '*Invoke-DomovoyCleanup*'
        $runner | Should -BeLike '*watchdog-cleanup-report.jsonl*'
        $runner | Should -BeLike '*Invoke-DomovoyAutoHeal*'
    }
}

Describe 'LSA audit (catalog 94)' {
    It 'reports the documented values read-only' {
        $status = Get-DomovoyLsaStatus
        $status.PSObject.Properties['RunAsPPL'] | Should -Not -BeNullOrEmpty
        $status.PSObject.Properties['RunAsPPLBootStart'] | Should -Not -BeNullOrEmpty
        $status.PSObject.Properties['LsaCfgFlags'] | Should -Not -BeNullOrEmpty
        $status.PSObject.Properties['RestrictReceivingNTLMTraffic'] | Should -Not -BeNullOrEmpty
        $status.PplConfigured | Should -BeOfType [bool]
        $status.Note | Should -Not -BeNullOrEmpty
    }
}

Describe 'Batch policy export for profiles (catalog 100)' {
    BeforeEach {
        $script:v11Features = Join-Path -Path (Get-PSDrive TestDrive).Root -ChildPath 'v11-export-features'
        New-Item -Path $script:v11Features -ItemType Directory -Force | Out-Null
        $env:DOMOVOY_FEATURES_DIR_BACKUP = $env:DOMOVOY_FEATURES_DIR
        $env:DOMOVOY_FEATURES_DIR = $script:v11Features

        foreach ($spec in @(
            @{ Id = 'v11.export.machine'; Name = 'Value'; Value = 0; ValueType = 'DWord'; Path = 'HKLM:\SOFTWARE\Policies\DomovoyExport' }
            @{ Id = 'v11.export.user'; Name = 'Label'; Value = 'hello'; ValueType = 'String'; Path = 'HKCU:\Software\DomovoyExport' }
            @{ Id = 'v11.export.outsider'; Name = 'Outsider'; Value = 7; ValueType = 'DWord'; Path = 'HKLM:\SOFTWARE\Policies\DomovoyExport' }
        )) {
            @{
                id = $spec.Id
                title = $spec.Id
                version = '1.0.0'
                category = 'privacy'
                risk = 'low'
                description = "Test fixture: $([string]$spec.Id)."
                ops = @(@{ type = 'registry.set'; path = $spec.Path; name = $spec.Name; value = $spec.Value; valueType = $spec.ValueType })
                undo = @{ mode = 'snapshot' }
                verify = @(@{ type = 'registry.set'; path = $spec.Path; name = $spec.Name; value = $spec.Value })
                references = @($script:registryRef)
            } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $script:v11Features "$($spec.Id).json") -Encoding UTF8
        }

        # The profile lists two of the three applied features; the outsider
        # must not leak into the export.
        $script:v11Profiles = Join-Path -Path (Get-PSDrive TestDrive).Root -ChildPath 'v11-profiles'
        New-Item -Path $script:v11Profiles -ItemType Directory -Force | Out-Null
        $env:DOMOVOY_PROFILES_DIR_BACKUP = $env:DOMOVOY_PROFILES_DIR
        $env:DOMOVOY_PROFILES_DIR = $script:v11Profiles
        @{
            id = 'v11test'
            title = 'V11 test profile'
            maxRisk = 'low'
            description = 'Test fixture profile.'
            features = @('v11.export.machine', 'v11.export.user')
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $script:v11Profiles 'v11test.json') -Encoding UTF8

        $null = Initialize-Domovoy
        $ledger = Join-Path -Path $env:DOMOVOY_STORE -ChildPath 'ledger.jsonl'
        @(
            @{ timestamp = '2026-11-02T11:00:00.000Z'; event = 'feature.apply'; featureId = 'v11.export.machine'; featureVersion = '1.0.0'; featureSource = (Join-Path $script:v11Features 'v11.export.machine.json'); snapshot = @(); verification = @{ AllPass = $true; Results = @() } }
            @{ timestamp = '2026-11-02T11:01:00.000Z'; event = 'feature.apply'; featureId = 'v11.export.user'; featureVersion = '1.0.0'; featureSource = (Join-Path $script:v11Features 'v11.export.user.json'); snapshot = @(); verification = @{ AllPass = $true; Results = @() } }
            @{ timestamp = '2026-11-02T11:02:00.000Z'; event = 'feature.apply'; featureId = 'v11.export.outsider'; featureVersion = '1.0.0'; featureSource = (Join-Path $script:v11Features 'v11.export.outsider.json'); snapshot = @(); verification = @{ AllPass = $true; Results = @() } }
        ) | ForEach-Object { $_ | ConvertTo-Json -Depth 8 -Compress } |
            Set-Content -LiteralPath $ledger -Encoding UTF8
    }

    AfterEach {
        $env:DOMOVOY_FEATURES_DIR = $env:DOMOVOY_FEATURES_DIR_BACKUP
        Remove-Item Env:DOMOVOY_FEATURES_DIR_BACKUP -ErrorAction SilentlyContinue
        $env:DOMOVOY_PROFILES_DIR = $env:DOMOVOY_PROFILES_DIR_BACKUP
        Remove-Item Env:DOMOVOY_PROFILES_DIR_BACKUP -ErrorAction SilentlyContinue
    }

    It 'exports exactly the profile features; the outsider stays out' {
        $out = Join-Path -Path (Get-PSDrive TestDrive).Root -ChildPath 'v11-export'
        $result = Export-DomovoyPolicy -ProfileId v11test -OutputDir $out -Force

        $result.SelfCheck | Should -BeLike 'pass*'
        $result.MachineEntries | Should -Be 1
        $result.UserEntries | Should -Be 1
        $mapping = Get-Content -LiteralPath $result.MappingCsv -Raw
        $mapping | Should -BeLike '*v11.export.machine*'
        $mapping | Should -BeLike '*v11.export.user*'
        $mapping | Should -Not -BeLike '*v11.export.outsider*'
    }

    It 'an unknown profile throws honestly' {
        $out = Join-Path -Path (Get-PSDrive TestDrive).Root -ChildPath 'v11-export-bad'
        { Export-DomovoyPolicy -ProfileId no.such.profile -OutputDir $out -Force } | Should -Throw
    }
}
