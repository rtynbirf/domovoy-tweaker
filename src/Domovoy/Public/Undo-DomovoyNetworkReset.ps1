function Undo-DomovoyNetworkReset {
    <#
    .SYNOPSIS
    Restores the removable network settings captured by the last network
    reset: static IPv4 addresses and DNS server lists.

    .DESCRIPTION
    Catalog feature 32, the undo half: the Winsock catalog itself cannot be
    restored after a reset - that is stated honestly up front - but the
    static IP and DNS settings snapshotted right before the reset CAN be
    restored. This command compares the current settings with the snapshot
    from the newest networkreset.apply ledger event and restores only what
    actually disappeared.

    Applying requires elevation (invariant I5).

    .EXAMPLE
    Undo-DomovoyNetworkReset
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param()

    $event = @(Get-DomovoyLedger -Event 'networkreset.apply' -Last 1000000) |
        Select-Object -Last 1

    if (-not $event) {
        throw 'No network reset found in the ledger. Nothing to undo.'
    }

    if (-not (Test-DomovoyAdmin)) {
        throw 'Restoring network settings requires an elevated PowerShell session.'
    }

    $snap = $event.snapshot
    $restoredIp = 0
    $restoredDns = 0
    $unchanged = 0

    if ($PSCmdlet.ShouldProcess('static IP and DNS settings', 'Restore from network reset snapshot')) {
        foreach ($item in @($snap.staticIp)) {
            $existing = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                Where-Object { $_.InterfaceIndex -eq $item.interfaceIndex -and $_.IPAddress -eq $item.ipAddress })
            if ($existing.Count -eq 0) {
                $null = New-NetIPAddress -InterfaceIndex $item.interfaceIndex `
                    -IPAddress $item.ipAddress -PrefixLength $item.prefixLength `
                    -ErrorAction SilentlyContinue
                if ($?) {
                    $restoredIp++
                }
            }
            else {
                $unchanged++
            }
        }

        foreach ($item in @($snap.dns)) {
            $current = Get-DnsClientServerAddress -InterfaceIndex $item.interfaceIndex `
                -AddressFamily IPv4 -ErrorAction SilentlyContinue
            $currentList = @($current.ServerAddresses)
            $wanted = @($item.serverAddresses)
            $same = ($currentList.Count -eq $wanted.Count)
            if ($same) {
                for ($i = 0; $i -lt $wanted.Count; $i++) {
                    if ($currentList[$i] -ne $wanted[$i]) {
                        $same = $false
                        break
                    }
                }
            }
            if (-not $same) {
                $null = Set-DnsClientServerAddress -InterfaceIndex $item.interfaceIndex `
                    -ServerAddresses $wanted -ErrorAction SilentlyContinue
                if ($?) {
                    $restoredDns++
                }
            }
            else {
                $unchanged++
            }
        }

        [pscustomobject]@{
            ResetFrom = $event.timestamp
            RestoredIpAddresses = $restoredIp
            RestoredDnsLists = $restoredDns
            AlreadyUnchanged = $unchanged
            Note = 'The Winsock catalog itself is not restorable and was not touched.'
        }
    }
}
