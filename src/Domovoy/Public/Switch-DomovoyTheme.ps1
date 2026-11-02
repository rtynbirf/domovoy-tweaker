function Switch-DomovoyTheme {
    <#
    .SYNOPSIS
    Toggles the Windows theme between dark and light as one switch (catalog 29).

    .DESCRIPTION
    Reads the current AppsUseLightTheme value and drives one of the two theme
    manifests (theme.dark / theme.light) through the SAME pipeline as the CLI:
    Invoke-DomovoyFeature. There is no side logic - the switch is resolved
    here, everything else (snapshot, verification, journal) is done by the
    standard contour, so undo works with the usual Undo-DomovoyFeature.

    Dry-run is the default (invariant I3): without -Apply the command only
    reports the resolved direction. Applying requires elevation because the
    shared pipeline checks it for every apply (invariant I5), even though the
    registry values themselves live in HKCU.

    .PARAMETER Theme
    Force the direction instead of toggling: Dark or Light.

    .PARAMETER Apply
    Perform the switch. Without it the command is a dry-run.

    .EXAMPLE
    Switch-DomovoyTheme

    .EXAMPLE
    Switch-DomovoyTheme -Apply

    .EXAMPLE
    Switch-DomovoyTheme -Theme Light -Apply
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [ValidateSet('Dark', 'Light')]
        [string]$Theme,

        [switch]$Apply
    )

    $personalize = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
    $current = Get-RegistryValueSafe -Path $personalize -Name 'AppsUseLightTheme'

    if ($Theme) {
        $target = $Theme.ToLowerInvariant()
    }
    else {
        # '<unset>' or an explicit 1 means the Windows default (light theme)
        # is active, so the switch goes dark; a live 0 goes back to light.
        if ([string]$current -eq '0') {
            $target = 'light'
        }
        else {
            $target = 'dark'
        }
    }

    if (-not $Apply) {
        [pscustomobject]@{
            CurrentAppsUseLightTheme = [string]$current
            TargetTheme = $target
            Mode = 'DryRun'
            Note = 'Dry-run by default. Add -Apply to switch the theme.'
        }
        return
    }

    if ($PSCmdlet.ShouldProcess("theme.$target", 'Switch Windows theme')) {
        Invoke-DomovoyFeature -Id "theme.$target" -Apply
    }
}
