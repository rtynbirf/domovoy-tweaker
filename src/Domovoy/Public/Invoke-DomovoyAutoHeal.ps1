function Invoke-DomovoyAutoHeal {
    <#
    .SYNOPSIS
    Scans for drift and re-applies drifted features (dry-run by default),
    recording the whole cycle in the ledger.

    .DESCRIPTION
    Catalog feature 58, the auto-heal contour: the drift scan works exactly
    like Invoke-DomovoyDriftScan (verified baseline from the ledger). Every
    drifted feature is healed by re-applying its manifest with
    Invoke-DomovoyFeature: the drifted state is snapshotted first (so the
    heal itself is undoable with Undo-DomovoyFeature), the operations run
    again and the post-apply verification lands in the ledger as a normal
    feature.apply event. One autoheal.cycle event summarizes the run.

    Honesty rules: dry-run by default (invariant I3); healing requires
    elevation when there is something to heal (invariant I5); a feature
    that cannot be re-applied (missing manifest, refused operation) lands
    in the failed list instead of being skipped silently. No restore point
    is created per heal (Windows allows one per 24 hours; the snapshot plus
    the ledger are the recovery path).

    .PARAMETER FeatureId
    Heal a single feature instead of all applied ones.

    .PARAMETER Trigger
    What started this cycle: Manual (default) or Scheduled (the watchdog
    task passes this so the ledger tells manual and scheduled cycles apart).

    .EXAMPLE
    Invoke-DomovoyAutoHeal

    .EXAMPLE
    Invoke-DomovoyAutoHeal -Apply
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [string]$FeatureId,

        [ValidateSet('Manual', 'Scheduled')]
        [string]$Trigger = 'Manual',

        [switch]$Apply
    )

    $scanParams = @{}
    if (-not [string]::IsNullOrEmpty($FeatureId)) {
        $scanParams['FeatureId'] = $FeatureId
    }
    $scan = Invoke-DomovoyDriftScan @scanParams

    $driftedIds = @($scan.Report |
        Where-Object { $_.Drifted } |
        Select-Object -ExpandProperty FeatureId)

    # Dry-run by default (invariant I3).
    if (-not $Apply) {
        [pscustomobject]@{
            Mode = 'DryRun'
            Trigger = $Trigger
            Scanned = $scan.Scanned
            Drifted = $scan.Drifted
            WouldHeal = $driftedIds
            Note = 'Healing re-applies the feature manifest; the drifted state is snapshotted first and stays undoable.'
        }
        return
    }

    # Elevation is only needed when there is something to heal (invariant I5).
    if ($driftedIds.Count -gt 0 -and -not (Test-DomovoyAdmin)) {
        throw 'Healing drifted features requires an elevated PowerShell session.'
    }

    $healed = @()
    $failed = @()
    foreach ($id in $driftedIds) {
        try {
            if (-not $PSCmdlet.ShouldProcess($id, 'Re-apply feature to heal drift')) {
                continue
            }
            # No restore point per heal: the snapshot plus the ledger are the
            # recovery path, and Windows allows one restore point per 24h.
            $null = Invoke-DomovoyFeature -Id $id -Apply -SkipRestorePoint -ErrorAction Stop
            $healed += $id
        }
        catch {
            $failed += @{
                featureId = $id
                reason = $_.Exception.Message
            }
        }
    }

    $written = Write-DomovoyLedgerEntry -Entry @{
        event = 'autoheal.cycle'
        trigger = $Trigger
        scanned = $scan.Scanned
        drifted = $scan.Drifted
        healed = @($healed)
        failed = @($failed)
    }

    [pscustomobject]@{
        Mode = 'Apply'
        Trigger = $Trigger
        Scanned = $scan.Scanned
        Drifted = $scan.Drifted
        Healed = @($healed)
        Failed = @($failed)
        LedgerTimestamp = $written['timestamp']
    }
}
