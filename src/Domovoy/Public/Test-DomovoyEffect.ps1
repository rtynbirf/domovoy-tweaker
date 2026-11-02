function Test-DomovoyEffect {
    <#
    .SYNOPSIS
    Runs verification probes for a feature and returns an honest pass/fail matrix.

    .DESCRIPTION
    Every probe asks the system one minimal question (registry value, service
    startup type) and compares the actual state with the expected one. A FAIL is
    a normal, honest answer - not an error.

    .EXAMPLE
    Test-DomovoyEffect -Id policy.telemetry.level0
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ById')]
        [string]$Id,

        [Parameter(Mandatory, ParameterSetName = 'ByManifest')]
        [psobject]$Manifest
    )

    if ($PSCmdlet.ParameterSetName -eq 'ById') {
        $feature = Get-DomovoyFeature -Id $Id
        if (-not $feature) {
            throw "Feature not found: $Id"
        }
        $Manifest = Read-FeatureManifest -Path $feature[0].File
    }

    $results = @()
    foreach ($probe in @($Manifest.verify)) {
        $target = $null
        $passOverride = $null
        $expected = $null
        $actual = $null

        switch ($probe.type) {
            'registry.set' {
                $target = '{0}\{1}' -f $probe.path, $probe.name
                $expected = [string]$probe.value
                $actual = Get-RegistryValueSafe -Path $probe.path -Name $probe.name
            }
            'service.startup' {
                $target = $probe.name
                $expected = [string]$probe.startupType
                $service = Get-Service -Name $probe.name -ErrorAction SilentlyContinue
                if ($service) {
                    $actual = [string]$service.StartType
                }
                else {
                    $actual = '<missing>'
                }
            }
            'registry.absent' {
                $target = '{0}\{1}' -f $probe.path, $probe.name
                $expected = '<unset>'
                $actual = Get-RegistryValueSafe -Path $probe.path -Name $probe.name
            }
            'service.status' {
                $target = $probe.name
                $expected = [string]$probe.expected
                $service = Get-Service -Name $probe.name -ErrorAction SilentlyContinue
                if ($service) {
                    $actual = [string]$service.Status
                }
                else {
                    $actual = '<missing>'
                }
            }
            'appx.absent' {
                $target = $probe.name
                $expected = '<absent>'
                $pkg = Get-AppxPackage -Name $probe.name -ErrorAction SilentlyContinue
                $actual = if ($pkg) { '<present>' } else { '<absent>' }
            }
            'file.attributes' {
                $target = $probe.path
                $requested = @($probe.attributes)
                $expected = ($requested -join ',')
                # -Force: a Hidden file is invisible to Get-Item without it,
                # so verification would fail right after apply sets the
                # attribute (Test-Path itself sees hidden files).
                if (Test-Path -LiteralPath $probe.path) {
                    $currentAttributes = (Get-Item -LiteralPath $probe.path -Force).Attributes
                    $present = @()
                    foreach ($attrName in $requested) {
                        if (($currentAttributes -band [System.IO.FileAttributes]::$attrName) -ne 0) {
                            $present += $attrName
                        }
                    }
                    $actual = ($present -join ',')
                }
                else {
                    $actual = '<missing>'
                }
            }
            'scheduler.taskState' {
                $target = '{0}{1}' -f $probe.taskPath, $probe.taskName
                $expected = [string]$probe.expected
                $task = Get-ScheduledTask -TaskPath $probe.taskPath -TaskName $probe.taskName -ErrorAction SilentlyContinue
                $actual = if ($task) { [string]$task.State } else { '<missing>' }
            }
            'network.dns' {
                $selector = $probe.interfaceAlias
                if ([string]::IsNullOrEmpty($selector)) { $selector = '*' }
                $target = $selector
                $expected = (@($probe.servers) | Sort-Object) -join ','
                $actualServers = @()
                foreach ($alias in (Get-DomovoyDnsTargets -InterfaceAlias $selector)) {
                    $dnsCurrent = Get-DnsClientServerAddress -InterfaceAlias $alias -AddressFamily IPv4 -ErrorAction SilentlyContinue
                    $actualServers += @($dnsCurrent.ServerAddresses)
                }
                $actual = (@($actualServers) | Sort-Object -Unique) -join ','
                if ([string]::IsNullOrEmpty($actual)) { $actual = '<unset>' }
            }
            'appx.present' {
                $target = $probe.name
                $expected = '<present>'
                $pkg = Get-AppxPackage -Name $probe.name -ErrorAction SilentlyContinue
                $actual = if ($pkg) { '<present>' } else { '<absent>' }
            }
            'network.proxy' {
                $proxyKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
                $target = 'WinINET (current user)'
                # The probe pins ProxyEnable and, when the manifest asks for a
                # concrete value, the server/PAC values too. '<unset>' is the
                # documented spelling of "the value does not exist"; '<any>'
                # (catalog 85) means "this dimension is not pinned".
                $triple = @{
                    enable = (Get-RegistryValueSafe -Path $proxyKey -Name 'ProxyEnable')
                    server = (Get-RegistryValueSafe -Path $proxyKey -Name 'ProxyServer')
                    pac = (Get-RegistryValueSafe -Path $proxyKey -Name 'AutoConfigURL')
                }
                $pins = @{
                    enable = [string]$probe.proxyEnable
                    server = [string]$probe.proxyServer
                    pac = [string]$probe.autoConfigUrl
                }
                $expected = 'enable={0};server={1};pac={2}' -f $pins.enable, $pins.server, $pins.pac
                $actual = 'enable={0};server={1};pac={2}' -f $triple.enable, $triple.server, $triple.pac
                $passOverride = $true
                foreach ($part in @('enable', 'server', 'pac')) {
                    if ($pins[$part] -ne '<any>' -and $pins[$part] -ne [string]$triple[$part]) {
                        $passOverride = $false
                    }
                }
            }
            'file.timestamp' {
                $target = $probe.path
                if (-not (Test-Path -LiteralPath $probe.path)) {
                    # The honest answer for a missing path.
                    $expected = 'pinned timestamps of an existing path'
                    $actual = '<missing>'
                }
                else {
                    $current = Get-DomovoyTimestampTriple -Path $probe.path
                    $expectedParts = @()
                    $actualParts = @()
                    $passOverride = $true
                    foreach ($field in @('creation', 'lastWrite', 'lastAccess')) {
                        $probeProp = $probe.PSObject.Properties[$field]
                        if ($probeProp) {
                            $expectedParts += '{0}={1}' -f $field, $probeProp.Value
                            $actualParts += '{0}={1}' -f $field, $current[$field]
                            $pinned = [DateTimeOffset]::Parse([string]$probeProp.Value,
                                [System.Globalization.CultureInfo]::InvariantCulture,
                                [System.Globalization.DateTimeStyles]::AssumeUniversal)
                            $seen = [DateTimeOffset]::Parse([string]$current[$field],
                                [System.Globalization.CultureInfo]::InvariantCulture,
                                [System.Globalization.DateTimeStyles]::AssumeUniversal)
                            if ($pinned.UtcDateTime -ne $seen.UtcDateTime) { $passOverride = $false }
                        }
                        else {
                            $expectedParts += '{0}=<any>' -f $field
                            $actualParts += '{0}=<any>' -f $field
                        }
                    }
                    $expected = ($expectedParts -join ';')
                    $actual = ($actualParts -join ';')
                }
            }
            'shell.handler.absent' {
                # Catalog 81: the handler registration key must be gone.
                $keyPath = '{0}:\Software\Classes\{1}\shellex\ContextMenuHandlers\{2}' -f $probe.hive, $probe.class, $probe.handler
                $target = $keyPath
                $expected = '<absent>'
                $actual = if (Test-Path -LiteralPath $keyPath) { '<present>' } else { '<absent>' }
            }
            'shell.handler.blocked' {
                # Catalog 81: the CLSID must appear in the documented
                # Blocked list (the registration itself stays untouched).
                $blockedKey = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked'
                $target = [string]$probe.clsid
                $expected = '<blocked>'
                $seen = Get-RegistryValueSafe -Path $blockedKey -Name $probe.clsid
                $actual = if ($seen -eq '<unset>') { '<unblocked>' } else { '<blocked>' }
            }
            'shell.openwith.absent' {
                # Catalog 81: the "Open with" suggestion must be gone
                # for the extension (per-user FileExts associations).
                $owKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\{0}\{1}' -f $probe.extension, $probe.kind
                $target = '{0}|{1}|{2}' -f $probe.extension, $probe.kind, $probe.entry
                $expected = '<absent>'
                $found = $false
                try {
                    $owItem = Get-Item -LiteralPath $owKey -ErrorAction Stop
                    if ($probe.kind -eq 'OpenWithList') {
                        foreach ($valueName in @($owItem.GetValueNames())) {
                            if ($valueName -ieq 'MRUList') { continue }
                            if ([string]$owItem.GetValue($valueName) -ieq [string]$probe.entry) {
                                $found = $true
                                break
                            }
                        }
                    }
                    else {
                        $found = ($null -ne $owItem.GetValue([string]$probe.entry))
                    }
                }
                catch {
                    $found = $false
                }
                $actual = if ($found) { '<present>' } else { '<absent>' }
            }
            default {
                $target = '<unknown-probe>'
                $expected = '?'
                $actual = '<unknown-probe>'
            }
        }

        $pass = if ($null -ne $passOverride) { $passOverride } else { ($actual -eq $expected) }

        $results += [pscustomobject]@{
            Probe = $probe.type
            Target = $target
            Expected = $expected
            Actual = $actual
            Pass = $pass
        }
    }

    $failed = @($results | Where-Object { -not $_.Pass })

    [pscustomobject]@{
        Feature = $Manifest.id
        AllPass = ($failed.Count -eq 0)
        Results = $results
    }
}
