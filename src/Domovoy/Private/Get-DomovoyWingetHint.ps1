function Get-DomovoyWingetHint {
    <#
    .SYNOPSIS
    Returns the documented winget package id for a removed Store package, or
    $null when no confident mapping exists.

    .DESCRIPTION
    Catalog feature 75: the undo of an appx.remove feature says honestly which
    documented source can restore the package. This helper adds the
    machine-readable winget identifier for the packages Domovoy itself ships
    manifests for. Domovoy never downloads anything (invariant I4) - the id is
    a hint for the user's own winget command. Ids current as of 2026-11;
    "winget search" remains the source of truth.

    .PARAMETER PackageName
    The Appx package name (for example "Microsoft.BingNews").

    .EXAMPLE
    Get-DomovoyWingetHint -PackageName "Microsoft.BingNews"
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$PackageName
    )

    # Only confident, commonly documented ids live here; anything else gets
    # the generic Store hint instead of an invented identifier.
    $map = @{
        'Microsoft.OneDriveSync'               = 'Microsoft.OneDrive'
        'MicrosoftTeams'                       = 'Microsoft.Teams'
        'Microsoft.XboxGamingOverlay'          = 'Microsoft.XboxGamingOverlay'
        'Microsoft.GetHelp'                    = 'Microsoft.GetHelp'
        'Microsoft.GetStarted'                 = 'Microsoft.GetStarted'
        'Microsoft.BingNews'                   = 'Microsoft.BingNews'
        'Microsoft.FeedbackHub'                = 'Microsoft.FeedbackHub'
        'Microsoft.MicrosoftSolitaireCollection' = 'Microsoft.MicrosoftSolitaireCollection'
    }

    if ($map.ContainsKey($PackageName)) {
        return [string]$map[$PackageName]
    }
    return $null
}
