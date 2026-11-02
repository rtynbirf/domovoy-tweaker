function Set-DomovoyFileOwner {
    <#
    .SYNOPSIS
    Shows the plan (dry-run by default) or changes the owner of a file or
    folder, recording the previous owner in the ledger.

    .DESCRIPTION
    Catalog feature 48: the same owner-change power Modern Tweaker's
    SetOwner had, rethought - the previous owner is ALWAYS captured before
    the change and can be restored with Undo-DomovoyFileOwner from the
    ledger. The privileges that make an ownership change possible
    (SeTakeOwnershipPrivilege, SeRestorePrivilege) are enabled through the
    journaled Enable-DomovoyPrivilege (catalog 52), so every elevation is
    visible in the ledger too.

    Applying requires elevation (invariant I5).

    .PARAMETER Path
    File or folder to change the owner of.

    .PARAMETER Owner
    Account in any NTAccount form (for example 'BUILTIN\Administrators'
    or 'DOMAIN\user').

    .EXAMPLE
    Set-DomovoyFileOwner -Path 'C:\Windows\System32\some.dll' -Owner 'BUILTIN\Administrators'

    .EXAMPLE
    Set-DomovoyFileOwner -Path 'C:\some\file.txt' -Owner 'BUILTIN\Administrators' -Apply
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Owner,

        [switch]$Apply
    )

    # Resolve the target account first: an unknown account is an immediate,
    # honest error instead of a half-applied change.
    $ntAccount = New-Object System.Security.Principal.NTAccount($Owner)
    $null = $ntAccount.Translate([System.Security.Principal.SecurityIdentifier])

    if (-not (Test-Path -LiteralPath $Path)) {
        throw ("Path not found: {0}" -f $Path)
    }

    $currentOwner = (Get-Acl -LiteralPath $Path).Owner

    # Dry-run by default (invariant I3).
    if (-not $Apply) {
        [pscustomobject]@{
            Mode = 'DryRun'
            Path = $Path
            CurrentOwner = $currentOwner
            NewOwner = $ntAccount.Value
        }
        return
    }

    # Elevation is checked explicitly (invariant I5).
    if (-not (Test-DomovoyAdmin)) {
        throw 'Changing file ownership requires an elevated PowerShell session.'
    }

    if ($PSCmdlet.ShouldProcess($Path, "Set owner to $($ntAccount.Value)")) {
        # Privileges that make an ownership change possible; each enable is
        # journaled by Enable-DomovoyPrivilege itself (catalog 52). Best
        # effort: a privilege not held by this token is reported, not fatal.
        foreach ($priv in @('SeTakeOwnershipPrivilege', 'SeRestorePrivilege')) {
            try {
                $null = Enable-DomovoyPrivilege -Name $priv -Apply
            }
            catch {
                Write-Verbose ("Privilege {0} was not enabled: {1}" -f $priv, $_.Exception.Message)
            }
        }

        $acl = Get-Acl -LiteralPath $Path
        $acl.SetOwner($ntAccount)
        Set-Acl -LiteralPath $Path -AclObject $acl

        $newOwner = (Get-Acl -LiteralPath $Path).Owner
        $verified = ($newOwner -eq $ntAccount.Value)

        $written = Write-DomovoyLedgerEntry -Entry @{
            event = 'fileowner.set'
            path = $Path
            previousOwner = $currentOwner
            newOwner = $newOwner
            verified = $verified
        }

        [pscustomobject]@{
            Mode = 'Apply'
            Path = $Path
            PreviousOwner = $currentOwner
            NewOwner = $newOwner
            Verified = $verified
            LedgerTimestamp = $written['timestamp']
        }
    }
}
