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
                # The probe pins the whole triple, so plain string equality
                # stays the single Pass rule; '<unset>' is the documented
                # spelling of "the value does not exist".
                $expected = 'enable={0};server={1};pac={2}' -f [string]$probe.proxyEnable, [string]$probe.proxyServer, [string]$probe.autoConfigUrl
                $actual = 'enable={0};server={1};pac={2}' -f (Get-RegistryValueSafe -Path $proxyKey -Name 'ProxyEnable'), (Get-RegistryValueSafe -Path $proxyKey -Name 'ProxyServer'), (Get-RegistryValueSafe -Path $proxyKey -Name 'AutoConfigURL')
            }
            default {
                $target = '<unknown-probe>'
                $expected = '?'
                $actual = '<unknown-probe>'
            }
        }

        $results += [pscustomobject]@{
            Probe = $probe.type
            Target = $target
            Expected = $expected
            Actual = $actual
            Pass = ($actual -eq $expected)
        }
    }

    $failed = @($results | Where-Object { -not $_.Pass })

    [pscustomobject]@{
        Feature = $Manifest.id
        AllPass = ($failed.Count -eq 0)
        Results = $results
    }
}
