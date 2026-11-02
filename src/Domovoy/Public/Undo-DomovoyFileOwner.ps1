function Undo-DomovoyFileOwner {
    <#
    .SYNOPSIS
    Restores the previous owner captured by the newest fileowner.set ledger
    event (dry-run by default).

    .DESCRIPTION
    Catalog feature 48, the undo half: the owner that was in place before
    the newest Set-DomovoyFileOwner -Apply is restored from the ledger
    snapshot. Applying requires elevation (invariant I5); the privileges
    used during the restore are journaled by Enable-DomovoyPrivilege.

    .EXAMPLE
    Undo-DomovoyFileOwner

    .EXAMPLE
    Undo-DomovoyFileOwner -Apply
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [switch]$Apply
    )

    $event = @(Get-DomovoyLedger -Event 'fileowner.set' -Last 1000000) |
        Select-Object -Last 1

    if (-not $event) {
        throw 'No owner change found in the ledger. Nothing to undo.'
    }

    if (-not (Test-Path -LiteralPath $event.path)) {
        throw ("The path no longer exists: {0}" -f $event.path)
    }

    $currentOwner = (Get-Acl -LiteralPath $event.path).Owner

    # Dry-run by default (invariant I3).
    if (-not $Apply) {
        [pscustomobject]@{
            Mode = 'DryRun'
            Path = $event.path
            ChangedAt = $event.timestamp
            CurrentOwner = $currentOwner
            WouldRestoreTo = $event.previousOwner
        }
        return
    }

    # Elevation is checked explicitly (invariant I5).
    if (-not (Test-DomovoyAdmin)) {
        throw 'Restoring file ownership requires an elevated PowerShell session.'
    }

    if ($PSCmdlet.ShouldProcess($event.path, "Restore owner $($event.previousOwner)")) {
        foreach ($priv in @('SeTakeOwnershipPrivilege', 'SeRestorePrivilege')) {
            try {
                $null = Enable-DomovoyPrivilege -Name $priv -Apply
            }
            catch {
                Write-Verbose ("Privilege {0} was not enabled: {1}" -f $priv, $_.Exception.Message)
            }
        }

        $target = New-Object System.Security.Principal.NTAccount($event.previousOwner)
        $acl = Get-Acl -LiteralPath $event.path
        $acl.SetOwner($target)
        Set-Acl -LiteralPath $event.path -AclObject $acl

        $restored = (Get-Acl -LiteralPath $event.path).Owner

        $written = Write-DomovoyLedgerEntry -Entry @{
            event = 'fileowner.undo'
            path = $event.path
            restoredOwner = $restored
            changedAt = $event.timestamp
        }

        [pscustomobject]@{
            Mode = 'Undo'
            Path = $event.path
            RestoredOwner = $restored
            LedgerTimestamp = $written['timestamp']
        }
    }
}
