function New-DomovoyRestorePoint {
    <#
    .SYNOPSIS
    Creates a Windows system restore point for Domovoy operations.

    .DESCRIPTION
    Wraps Checkpoint-Computer (MODIFY_SETTINGS). Windows limits restore point
    creation to once per 24 hours by default; the caller should treat a failure
    here as soft.

    .EXAMPLE
    New-DomovoyRestorePoint -Description 'Domovoy: before profile minimum'
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [string]$Description = 'Domovoy manual checkpoint'
    )

    if (-not (Test-DomovoyAdmin)) {
        throw 'Creating a restore point requires an elevated PowerShell session.'
    }

    if ($PSCmdlet.ShouldProcess($Description, 'Create system restore point')) {
        Checkpoint-Computer -Description $Description -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
    }

    [pscustomobject]@{
        Created = $true
        Description = $Description
    }
}
