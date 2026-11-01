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
        $verification = Test-DomovoyEffect -Id $applied.featureId
        $report += [pscustomobject]@{
            FeatureId = $applied.featureId
            AppliedAt = $applied.timestamp
            Drifted = (-not $verification.AllPass)
            Details = $verification.Results
        }
    }

    $drifted = @($report | Where-Object { $_.Drifted })

    [pscustomobject]@{
        Scanned = @($report).Count
        Drifted = $drifted.Count
        Report = $report
    }
}
