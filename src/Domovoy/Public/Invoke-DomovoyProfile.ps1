function Invoke-DomovoyProfile {
    <#
    .SYNOPSIS
    Shows the combined dry-run plan for a whole profile (default) or applies it
    feature by feature.

    .DESCRIPTION
    Resolves the profile, filters out features whose risk exceeds the profile's
    maxRisk (reported honestly as skipped), creates ONE system restore point for
    the whole run and then drives Invoke-DomovoyFeature for every remaining
    feature. Without -Apply nothing is changed (invariant I3): the result is the
    combined plan. A failing feature does not abort the profile - its error is
    collected in the report.

    .PARAMETER Id
    Profile id (see Get-DomovoyProfile).

    .PARAMETER Apply
    Apply every feature in the profile (elevation still enforced per feature).

    .PARAMETER SkipRestorePoint
    Skip the single profile-level restore point.

    .EXAMPLE
    Invoke-DomovoyProfile -Id cautious

    .EXAMPLE
    Invoke-DomovoyProfile -Id cautious -Apply
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$Id,

        [switch]$Apply,

        [switch]$SkipRestorePoint
    )

    $resolved = @(Get-DomovoyProfile -Id $Id)
    if ($resolved.Count -eq 0) {
        throw "Profile not found: $Id"
    }
    if ($resolved.Count -gt 1) {
        throw ("Multiple profiles with id '{0}' found." -f $Id)
    }
    $profileDef = $resolved[0]

    $riskOrder = @{ low = 0; medium = 1; high = 2 }
    $maxRisk = $riskOrder[$profileDef.MaxRisk]

    # One restore point for the whole profile (not one per feature).
    if ($Apply -and -not $SkipRestorePoint) {
        try {
            New-DomovoyRestorePoint -Description "Domovoy profile: $($profileDef.Id)" -ErrorAction Stop | Out-Null
        }
        catch {
            Write-Verbose ("Restore point was not created: {0}" -f $_.Exception.Message)
        }
    }

    $applied = @()
    $skipped = @()
    foreach ($featureId in @($profileDef.Features)) {
        $feature = @(Get-DomovoyFeature -Id $featureId)
        if ($feature.Count -eq 0) {
            $skipped += [pscustomobject]@{
                Feature = $featureId
                Reason = 'manifest not found'
            }
            continue
        }

        if ($riskOrder[$feature[0].Risk] -gt $maxRisk) {
            $skipped += [pscustomobject]@{
                Feature = $featureId
                Reason = ("risk '{0}' exceeds profile max '{1}'" -f $feature[0].Risk, $profileDef.MaxRisk)
            }
            continue
        }

        if ($Apply) {
            if (-not $PSCmdlet.ShouldProcess($featureId, 'Apply profile feature')) {
                continue
            }
            try {
                $applied += Invoke-DomovoyFeature -Id $featureId -Apply -SkipRestorePoint
            }
            catch {
                # Honest report: a failing feature is collected, not hidden.
                $applied += [pscustomobject]@{
                    Feature = $featureId
                    Mode = 'Apply'
                    Error = $_.Exception.Message
                    Verification = $null
                    LedgerTimestamp = $null
                }
            }
        }
        else {
            $applied += Invoke-DomovoyFeature -Id $featureId
        }
    }

    [pscustomobject]@{
        Profile = $profileDef.Id
        Mode = if ($Apply) { 'Apply' } else { 'DryRun' }
        MaxRisk = $profileDef.MaxRisk
        Applied = $applied
        Skipped = $skipped
    }
}
