function Invoke-DomovoyDriftScan {
    <#
    .SYNOPSIS
    Scans every applied feature for drift between the actual system state and
    the expected one.

    .DESCRIPTION
    Takes the most recent feature.apply event per feature from the ledger, runs
    the verification probes and reports which features drifted (for example,
    rolled back by a Windows update).

    .PARAMETER FeatureId
    Scan a single feature instead of all applied ones.

    .EXAMPLE
    Invoke-DomovoyDriftScan
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string]$FeatureId
    )

    if (-not (Test-Path (Get-DomovoyStorePath -SubPath 'ledger.jsonl'))) {
        Write-Warning 'Ledger not found. Nothing was ever applied by Domovoy.'
        return [pscustomobject]@{
            Scanned = 0
            Drifted = 0
            Report = @()
        }
    }

    $latest = Get-DomovoyLedger -Event 'feature.apply' -Last 1000000 |
        Group-Object -Property featureId |
        ForEach-Object { $_.Group | Select-Object -Last 1 }

    if (-not [string]::IsNullOrEmpty($FeatureId)) {
        $latest = @($latest | Where-Object { $_.featureId -eq $FeatureId })
    }

    $report = @()
    foreach ($applied in @($latest)) {
        try {
            $manifest = Get-DomovoyManifestForFeature -Id $applied.featureId -LedgerEntry $applied
            $verification = Test-DomovoyEffect -Manifest $manifest
            $drifted = -not $verification.AllPass
            $details = $verification.Results
        }
        catch {
            $drifted = $true
            $details = @([pscustomobject]@{
                Probe = 'manifest'
                Target = $applied.featureId
                Expected = 'readable manifest'
                Actual = '<unresolved>'
                Pass = $false
            })
        }
        $report += [pscustomobject]@{
            FeatureId = $applied.featureId
            AppliedAt = $applied.timestamp
            Drifted = $drifted
            Details = $details
        }
    }

    $drifted = @($report | Where-Object { $_.Drifted })

    [pscustomobject]@{
        Scanned = @($report).Count
        Drifted = $drifted.Count
        Report = $report
    }
}
