function Restore-DomovoyNetworkState {
    <#
    .SYNOPSIS
    Restores network settings (DNS, proxy) captured by Export-DomovoyNetworkState.

    .DESCRIPTION
    Builds a synthetic feature manifest from the captured JSON, writes it into
    the Domovoy store (it stays there as the featureSource recorded in the
    journal, so undo and auto-heal keep working) and runs it through the SAME
    pipeline as any other manifest: Invoke-DomovoyFeature. That is where the
    invariants live - a snapshot before the change, verification probes after,
    one feature.apply event per cycle and per-feature undo. No logic is
    duplicated here.

    Dry-run is the default (invariant I3): without -Apply the command shows
    the plan only. Adapters for which the export captured no explicit DNS
    servers are reported and skipped - the manifest schema requires at least
    one server, and pretending to "restore nothing" would be a lie.

    .PARAMETER Path
    The JSON file produced by Export-DomovoyNetworkState.

    .PARAMETER Apply
    Perform the restore. Without it the command is a dry-run.

    .PARAMETER SkipRestorePoint
    Do not ask Windows for a system restore point before applying.

    .EXAMPLE
    Restore-DomovoyNetworkState -Path network-state-20261102-120000.json

    .EXAMPLE
    Restore-DomovoyNetworkState -Path network-state.json -Apply
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [switch]$Apply,

        [switch]$SkipRestorePoint
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Network state file not found: $Path"
    }
    $state = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($state.kind -ne 'domovoy-network-state') {
        throw 'Not a Domovoy network state export (kind mismatch).'
    }

    $ops = @()
    $verify = @()
    $skipped = @()

    foreach ($dnsEntry in @($state.dns)) {
        $servers = @($dnsEntry.servers) | Where-Object { $_ -and ($_ -ne '<unset>') }
        if (@($servers).Count -eq 0) {
            $skipped += ("{0}: no explicit DNS servers were captured" -f $dnsEntry.interfaceAlias)
            continue
        }
        $ops += @{
            type = 'network.dns'
            interfaceAlias = [string]$dnsEntry.interfaceAlias
            servers = @($servers)
        }
        $verify += @{
            type = 'network.dns'
            interfaceAlias = [string]$dnsEntry.interfaceAlias
            servers = @($servers)
        }
    }

    $proxy = $state.proxy
    if ($proxy -and ([string]$proxy.proxyEnable -ne '<unset>')) {
        if ([string]$proxy.proxyEnable -eq '1') {
            if ($proxy.autoConfigUrl -and ($proxy.autoConfigUrl -ne '<unset>')) {
                $ops += @{
                    type = 'network.proxy'
                    mode = 'pac'
                    autoConfigUrl = [string]$proxy.autoConfigUrl
                }
                $verify += @{
                    type = 'network.proxy'
                    proxyEnable = 1
                    proxyServer = [string]$proxy.proxyServer
                    autoConfigUrl = [string]$proxy.autoConfigUrl
                }
            }
            elseif ($proxy.proxyServer -and ($proxy.proxyServer -ne '<unset>')) {
                $proxyOp = @{
                    type = 'network.proxy'
                    mode = 'server'
                    proxyServer = [string]$proxy.proxyServer
                }
                $proxyProbe = @{
                    type = 'network.proxy'
                    proxyEnable = 1
                    proxyServer = [string]$proxy.proxyServer
                    autoConfigUrl = [string]$proxy.autoConfigUrl
                }
                if (([string]$proxy.proxyOverride) -match '<local>') {
                    $proxyOp.bypassLocal = $true
                }
                $ops += $proxyOp
                $verify += $proxyProbe
            }
            else {
                $skipped += 'proxy: enabled, but neither a server nor a PAC URL was captured'
            }
        }
        else {
            $ops += @{
                type = 'network.proxy'
                mode = 'off'
            }
            $verify += @{
                type = 'network.proxy'
                proxyEnable = 0
                proxyServer = [string]$proxy.proxyServer
                autoConfigUrl = [string]$proxy.autoConfigUrl
            }
        }
    }
    elseif ($proxy) {
        # ProxyEnable itself was never set on the source machine: the honest
        # restore is to keep it unset, not to create ProxyEnable = 0.
        $skipped += 'proxy: no ProxyEnable value was captured (the proxy was never configured)'
    }

    if (@($ops).Count -eq 0) {
        foreach ($note in $skipped) {
            Write-Warning $note
        }
        throw 'Nothing to restore: the export carries no explicit DNS servers or proxy settings.'
    }

    $manifest = [ordered]@{
        id = 'network.state.restore'
        title = 'Network state restore (generated from an export)'
        version = '1.0.0'
        category = 'network'
        risk = 'medium'
        description = 'Generated by Restore-DomovoyNetworkState from a JSON export made by Export-DomovoyNetworkState. Applying runs through the standard pipeline: snapshot before the change, verification probes after, a feature.apply event in the journal and per-feature undo.'
        ops = $ops
        undo = @{
            mode = 'snapshot'
        }
        verify = $verify
        references = @('https://learn.microsoft.com/windows/win32/sysinfo/registry')
    }

    # The generated manifest lives in the store: the journal records it as
    # featureSource, and both Undo-DomovoyFeature and auto-heal resolve the
    # feature through that path later.
    $manifestPath = Get-DomovoyStorePath -SubPath 'generated/network.state.restore.json'
    $json = $manifest | ConvertTo-Json -Depth 6
    [System.IO.File]::WriteAllText($manifestPath, $json, [System.Text.UTF8Encoding]::new($false))

    if ($Apply) {
        Invoke-DomovoyFeature -ManifestFile $manifestPath -Apply -SkipRestorePoint:$SkipRestorePoint
    }
    else {
        $plan = Invoke-DomovoyFeature -ManifestFile $manifestPath
        [pscustomobject]@{
            Feature = 'network.state.restore'
            Mode = 'DryRun'
            ManifestFile = $manifestPath
            Skipped = $skipped
            Plan = $plan.Plan
        }
    }
}
