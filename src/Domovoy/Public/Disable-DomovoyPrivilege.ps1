function Disable-DomovoyPrivilege {
    <#
    .SYNOPSIS
    Disables one named privilege in the current process token (dry-run by
    default) and records the change in the ledger.

    .DESCRIPTION
    Catalog feature 52: the journaled inverse of Enable-DomovoyPrivilege.
    The change affects the current process only.

    .PARAMETER Name
    Privilege name in the Se*Privilege form.

    .EXAMPLE
    Disable-DomovoyPrivilege -Name SeTakeOwnershipPrivilege -Apply
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidatePattern('^Se[A-Za-z]+Privilege$')]
        [string]$Name,

        [switch]$Apply
    )

    process {
        $current = 'Disabled'
        foreach ($priv in @(Get-DomovoyPrivilege)) {
            if ($priv.Name -eq $Name) { $current = $priv.State }
        }

        if (-not $Apply) {
            [pscustomobject]@{
                Mode = 'DryRun'
                Privilege = $Name
                CurrentState = $current
                WouldChangeTo = 'Disabled'
            }
            return
        }

        if ($PSCmdlet.ShouldProcess($Name, 'Disable privilege in the current process token')) {
            $result = Set-DomovoyTokenPrivilege -Name $Name -Enable $false
            $written = Write-DomovoyLedgerEntry -Entry @{
                event = 'privilege.disable'
                privilege = $Name
                previousState = $result.PreviousState
            }

            [pscustomobject]@{
                Mode = 'Apply'
                Privilege = $Name
                State = 'Disabled'
                PreviousState = $result.PreviousState
                LedgerTimestamp = $written['timestamp']
            }
        }
    }
}
