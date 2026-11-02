function Invoke-DomovoyNetworkReset {
    <#
    .SYNOPSIS
    Shows the network reset plan (dry-run by default) or resets the Winsock
    catalog and/or the TCP/IP stack, with a snapshot of every removable
    setting.

    .DESCRIPTION
    Catalog feature 32: an explicit feature instead of a hidden command line.
    A Winsock or TCP/IP reset is irreversible for the Winsock catalog itself
    (third-party LSP entries cannot be restored), so this command is honest
    about it: the reset itself is not undoable, but every setting that CAN be
    captured is captured - static IPv4 addresses and DNS server lists of all
    interfaces are snapshotted before the reset and can be restored by
    Undo-DomovoyNetworkReset if the reset removed them.

    Dry-run is the default (invariant I3). Applying requires elevation
    (invariant I5) and appends a networkreset.apply event with the snapshot
    to the ledger. A reboot is usually required after the reset.

    .PARAMETER Target
    Winsock - reset the Winsock catalog; IP - reset the TCP/IP stack;
    All - both (default).

    .PARAMETER Apply
    Perform the reset. Without this switch only the plan is shown.

    .EXAMPLE
    Invoke-DomovoyNetworkReset

    .EXAMPLE
    Invoke-DomovoyNetworkReset -Target Winsock -Apply
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [ValidateSet('Winsock', 'IP', 'All')]
        [string]$Target = 'All',

        [switch]$Apply
    )

    $commands = @()
    switch ($Target) {
        'Winsock' { $commands += 'netsh winsock reset' }
        'IP' { $commands += 'netsh int ip reset' }
        'All' {
            $commands += 'netsh winsock reset'
            $commands += 'netsh int ip reset'
        }
    }

    if (-not $Apply) {
        [pscustomobject]@{
            Target = $Target
            Mode = 'DryRun'
            Commands = $commands
            RemovableSnapshot = 'static IPv4 addresses and DNS server lists of all interfaces'
            UndoablePart = 'removable settings only (Undo-DomovoyNetworkReset)'
            Note = 'The Winsock catalog itself cannot be restored; a reboot is usually required.'
        }
        return
    }

    if (-not (Test-DomovoyAdmin)) {
        throw 'Applying a network reset requires an elevated PowerShell session.'
    }

    if ($PSCmdlet.ShouldProcess($Target, 'Reset network components')) {
        # Snapshot every removable setting before touching anything (I2).
        $staticIp = @()
        foreach ($ip in @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                Where-Object { $_.PrefixOrigin -eq 'Manual' })) {
            $staticIp += @{
                interfaceIndex = $ip.InterfaceIndex
                interfaceAlias = $ip.InterfaceAlias
                ipAddress = $ip.IPAddress
                prefixLength = $ip.PrefixLength
            }
        }

        $dns = @()
        foreach ($entry in @(Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue)) {
            if (@($entry.ServerAddresses).Count -gt 0) {
                $dns += @{
                    interfaceIndex = $entry.InterfaceIndex
                    interfaceAlias = $entry.InterfaceAlias
                    serverAddresses = @($entry.ServerAddresses)
                }
            }
        }

        $results = @()
        foreach ($command in $commands) {
            $parts = $command.Split(' ')
            $exe = $parts[0]
            $arguments = $parts[1..($parts.Length - 1)]
            $output = & $exe @arguments 2>&1
            $results += @{
                command = $command
                exitCode = $LASTEXITCODE
                output = (@($output) -join "`n")
            }
        }

        $written = Write-DomovoyLedgerEntry -Entry @{
            event = 'networkreset.apply'
            featureId = 'network.' + $Target.ToLowerInvariant() + '.reset'
            target = $Target
            commands = $results
            snapshot = @{
                staticIp = $staticIp
                dns = $dns
            }
            rebootRecommended = $true
        }

        [pscustomobject]@{
            Target = $Target
            Mode = 'Apply'
            Commands = $results
            StaticIpSnapshotted = @($staticIp).Count
            DnsSnapshotted = @($dns).Count
            RebootRecommended = $true
            LedgerTimestamp = $written['timestamp']
        }
    }
}
