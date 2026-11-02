function Get-DomovoyNetworkReport {
    <#
    .SYNOPSIS
    Reports the network state: adapters, addresses, DNS, proxy (catalog 33).

    .DESCRIPTION
    Read-only, changes nothing (reports never touch the system). One flat list
    of rows so it can be eyeballed, filtered and piped:

      Get-DomovoyNetworkReport | Where-Object Section -eq 'dns'

    Sources: Get-NetAdapter and Get-NetIPAddress for adapters and addresses,
    Get-DnsClientServerAddress and Get-DnsClientGlobalSetting for DNS, the
    WinINET values for the per-user proxy (the same four values the
    network.proxy op snapshots) and `netsh winhttp show proxy` for the
    machine-wide proxy. Every source is wrapped so a missing subsystem
    degrades to fewer rows, never to a failed report.

    .EXAMPLE
    Get-DomovoyNetworkReport

    .EXAMPLE
    Get-DomovoyNetworkReport | Format-Table -AutoSize
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $rows = @()

    # Adapters.
    $adapters = @()
    try {
        $adapters = @(Get-NetAdapter -ErrorAction SilentlyContinue)
    }
    catch { }
    foreach ($adapter in $adapters) {
        $rows += [pscustomobject]@{
            Section = 'adapter'
            Name = [string]$adapter.Name
            Value = ('{0}; {1}; {2}' -f $adapter.Status, $adapter.InterfaceDescription, $adapter.MacAddress)
        }
    }

    # IPv4 addresses.
    $addresses = @()
    try {
        $addresses = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue)
    }
    catch { }
    foreach ($address in $addresses) {
        $rows += [pscustomobject]@{
            Section = 'ip'
            Name = [string]$address.InterfaceAlias
            Value = ('{0} (prefix {1})' -f $address.IPAddress, $address.PrefixLength)
        }
    }

    # Per-adapter DNS servers (IPv4, the family the network.dns op manages).
    $dnsEntries = @()
    try {
        $dnsEntries = @(Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue)
    }
    catch { }
    foreach ($dnsEntry in $dnsEntries) {
        if (@($dnsEntry.ServerAddresses).Count -eq 0) {
            continue
        }
        $rows += [pscustomobject]@{
            Section = 'dns'
            Name = [string]$dnsEntry.InterfaceAlias
            Value = (@($dnsEntry.ServerAddresses) -join ', ')
        }
    }

    # Global DNS settings.
    try {
        $globalDns = Get-DnsClientGlobalSetting -ErrorAction SilentlyContinue
        if ($globalDns) {
            $rows += [pscustomobject]@{
                Section = 'dns-global'
                Name = 'SuffixSearchList'
                Value = [string]$globalDns.SuffixSearchList
            }
        }
    }
    catch { }

    # WinINET proxy (current user).
    $proxyKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
    $proxyValues = @(
        @{ Name = 'ProxyEnable'; Value = [string](Get-RegistryValueSafe -Path $proxyKey -Name 'ProxyEnable') }
        @{ Name = 'ProxyServer'; Value = [string](Get-RegistryValueSafe -Path $proxyKey -Name 'ProxyServer') }
        @{ Name = 'AutoConfigURL'; Value = [string](Get-RegistryValueSafe -Path $proxyKey -Name 'AutoConfigURL') }
        @{ Name = 'ProxyOverride'; Value = [string](Get-RegistryValueSafe -Path $proxyKey -Name 'ProxyOverride') }
    )
    foreach ($proxyValue in $proxyValues) {
        $rows += [pscustomobject]@{
            Section = 'proxy-wininet'
            Name = $proxyValue.Name
            Value = $proxyValue.Value
        }
    }

    # WinHTTP proxy (machine-wide) via the documented read-only netsh query.
    try {
        $winhttp = netsh winhttp show proxy 2>$null
        if ($LASTEXITCODE -eq 0 -and $winhttp) {
            $rows += [pscustomobject]@{
                Section = 'proxy-winhttp'
                Name = 'netsh winhttp show proxy'
                Value = (@($winhttp | Where-Object { $_ -match '\S' }) -join ' | ')
            }
        }
    }
    catch { }

    return $rows
}
