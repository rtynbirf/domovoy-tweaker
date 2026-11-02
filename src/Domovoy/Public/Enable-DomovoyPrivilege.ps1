function Enable-DomovoyPrivilege {
    <#
    .SYNOPSIS
    Enables one named privilege in the current process token (dry-run by
    default) and records the change in the ledger.

    .DESCRIPTION
    Catalog feature 52: the same power Modern Tweaker used for
    TrustedInstaller-style scenarios (AdjustTokenPrivileges), but every
    elevation is visible and journaled as a privilege.enable event. The
    change affects the current process only - it dies with the process.

    Without -Apply the command shows the current state and what would change.

    .PARAMETER Name
    Privilege name in the Se*Privilege form, for example
    SeTakeOwnershipPrivilege.

    .EXAMPLE
    Enable-DomovoyPrivilege -Name SeTakeOwnershipPrivilege

    .EXAMPLE
    Enable-DomovoyPrivilege -Name SeTakeOwnershipPrivilege -Apply
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
                WouldChangeTo = 'Enabled'
            }
            return
        }

        if ($PSCmdlet.ShouldProcess($Name, 'Enable privilege in the current process token')) {
            $result = Set-DomovoyTokenPrivilege -Name $Name -Enable $true
            $written = Write-DomovoyLedgerEntry -Entry @{
                event = 'privilege.enable'
                privilege = $Name
                previousState = $result.PreviousState
            }

            [pscustomobject]@{
                Mode = 'Apply'
                Privilege = $Name
                State = 'Enabled'
                PreviousState = $result.PreviousState
                LedgerTimestamp = $written['timestamp']
            }
        }
    }
}
