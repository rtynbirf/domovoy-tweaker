function Export-DomovoyNetworkState {
    <#
    .SYNOPSIS
    Exports the current network settings (DNS, proxy) to a JSON file (catalog 35).

    .DESCRIPTION
    Read-only: nothing on the system is touched and nothing is written to the
    journal. DNS servers are collected through the same adapter resolution the
    network.dns op uses, so an export and a later restore always see the same
    adapter set. The WinINET proxy block carries exactly the values the
    network.proxy op snapshots. Restore-DomovoyNetworkState consumes the file.

    .PARAMETER Path
    Target JSON file. Defaults to a timestamped file inside the Domovoy store.

    .EXAMPLE
    Export-DomovoyNetworkState

    .EXAMPLE
    Export-DomovoyNetworkState -Path D:\backup\network.json
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string]$Path
    )

    $dns = @()
    foreach ($alias in @(Get-DomovoyDnsTargets -InterfaceAlias '*')) {
        $servers = @()
        $current = Get-DnsClientServerAddress -InterfaceAlias $alias -AddressFamily IPv4 -ErrorAction SilentlyContinue
        if ($current) {
            $servers = @($current.ServerAddresses)
        }
        $dns += @{
            interfaceAlias = $alias
            servers = @($servers)
        }
    }

    # The same four WinINET values the network.proxy op captures in snapshots.
    $proxyKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
    $proxy = @{
        proxyEnable = [string](Get-RegistryValueSafe -Path $proxyKey -Name 'ProxyEnable')
        proxyServer = [string](Get-RegistryValueSafe -Path $proxyKey -Name 'ProxyServer')
        autoConfigUrl = [string](Get-RegistryValueSafe -Path $proxyKey -Name 'AutoConfigURL')
        proxyOverride = [string](Get-RegistryValueSafe -Path $proxyKey -Name 'ProxyOverride')
    }

    $state = [pscustomobject]@{
        schemaVersion = 1
        kind = 'domovoy-network-state'
        exportedAt = [DateTimeOffset]::UtcNow.ToString('o')
        dns = $dns
        proxy = $proxy
    }

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
        $Path = Get-DomovoyStorePath -SubPath ("network-state-{0}.json" -f $stamp)
    }

    $json = $state | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText($Path, $json, [System.Text.UTF8Encoding]::new($false))

    [pscustomobject]@{
        Path = $Path
        Adapters = @($dns).Count
        ProxyEnable = $proxy.proxyEnable
    }
}
