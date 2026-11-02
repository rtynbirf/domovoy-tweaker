function Invoke-DomovoyDriftScan {
    <#
    .SYNOPSIS
    Scans every currently applied feature for drift between the verified
    post-apply state and the actual system state right now.

    .DESCRIPTION
    Since v0.4 the baseline comes from the ledger, not from the manifest. For
    each feature the most recent feature.apply event stores the verification
    probe results - the verified state of the system right after apply. The
    scan re-runs the same probes and reports every probe whose actual value no
    longer matches that verified baseline (for example, a policy rolled back
    by a Windows update).

    Features whose most recent ledger event is feature.undo are not applied
    anymore and are not scanned. Probes without a recorded baseline fall back
    to the manifest expectation and stay marked as such in the details.

    .PARAMETER FeatureId
    Scan a single feature instead of all applied ones.

    .PARAMETER Since
    Only scan features whose last apply happened at or after this moment.

    .EXAMPLE
    Invoke-DomovoyDriftScan

    .EXAMPLE
    Invoke-DomovoyDriftScan -Since (Get-Date).AddDays(-7)
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string]$FeatureId,

        [datetime]$Since
    )

    $detectedAt = [DateTimeOffset]::UtcNow.ToString('o')

    if (-not (Test-Path (Get-DomovoyStorePath -SubPath 'ledger.jsonl'))) {
        Write-Warning 'Ledger not found. Nothing was ever applied by Domovoy.'
        return [pscustomobject]@{
            Scanned = 0
            Drifted = 0
            DetectedAt = $detectedAt
            Report = @()
        }
    }

    # Latest apply/undo event per feature: a feature whose newest event is an
    # undo is not applied anymore and therefore is not scanned.
    $latest = Get-DomovoyLedger -Last 1000000 |
        Where-Object { $_.event -in @('feature.apply', 'feature.undo') } |
        Group-Object -Property featureId |
        ForEach-Object { $_.Group | Select-Object -Last 1 } |
        Where-Object { $_.event -eq 'feature.apply' }

    if ($PSBoundParameters.ContainsKey('Since')) {
        $sinceOffset = [DateTimeOffset]$Since
        $latest = @($latest | Where-Object { [DateTimeOffset]$_.timestamp -ge $sinceOffset })
    }

    if (-not [string]::IsNullOrEmpty($FeatureId)) {
        $latest = @($latest | Where-Object { $_.featureId -eq $FeatureId })
    }

    $report = @()
    foreach ($applied in @($latest)) {
        try {
            $manifest = Get-DomovoyManifestForFeature -Id $applied.featureId -LedgerEntry $applied
            $current = Test-DomovoyEffect -Manifest $manifest
        }
        catch {
            $report += [pscustomobject]@{
                FeatureId = $applied.featureId
                AppliedAt = $applied.timestamp
                DetectedAt = $detectedAt
                Drifted = $true
                Details = @([pscustomobject]@{
                    Probe = 'manifest'
                    Target = $applied.featureId
                    Verified = '<unverified>'
                    Expected = 'readable manifest'
                    Actual = '<unresolved>'
                    Pass = $false
                })
            }
            continue
        }

        # Baseline: the verified post-apply probe results recorded in the
        # ledger, keyed by probe type and target.
        $baseline = @{}
        if ($applied.PSObject.Properties['verification'] -and
            $applied.verification -and $applied.verification.Results) {
            foreach ($recorded in @($applied.verification.Results)) {
                $baseline['{0}|{1}' -f $recorded.Probe, $recorded.Target] = [string]$recorded.Actual
            }
        }

        $details = @()
        foreach ($probe in @($current.Results)) {
            $key = '{0}|{1}' -f $probe.Probe, $probe.Target
            if ($baseline.ContainsKey($key)) {
                $verified = $baseline[$key]
            }
            else {
                # No recorded baseline for this probe - fall back to the
                # manifest expectation and say so honestly.
                $verified = $probe.Expected
            }
            $details += [pscustomobject]@{
                Probe = $probe.Probe
                Target = $probe.Target
                Verified = $verified
                Expected = $probe.Expected
                Actual = $probe.Actual
                Pass = ($probe.Actual -eq $verified)
            }
        }

        $drifted = @($details | Where-Object { -not $_.Pass }).Count -gt 0

        $report += [pscustomobject]@{
            FeatureId = $applied.featureId
            AppliedAt = $applied.timestamp
            DetectedAt = $detectedAt
            Drifted = $drifted
            Details = $details
        }
    }

    $drifted = @($report | Where-Object { $_.Drifted })

    [pscustomobject]@{
        Scanned = @($report).Count
        Drifted = $drifted.Count
        DetectedAt = $detectedAt
        Report = $report
    }
}
