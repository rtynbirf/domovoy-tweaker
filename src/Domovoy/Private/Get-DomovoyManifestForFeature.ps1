function Get-DomovoyManifestForFeature {
    <#
    .SYNOPSIS
    Resolves a feature manifest by id: feature directory first, then the
    featureSource path recorded in the ledger entry.

    .NOTES
    The ledger fallback makes undo and drift scan work even when the manifest
    file has been moved or lives outside the feature directory (v0.2).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$Id,

        [AllowNull()]
        [psobject]$LedgerEntry
    )

    try {
        $feature = Get-DomovoyFeature -Id $Id
        if ($feature) {
            return Read-FeatureManifest -Path $feature[0].File
        }
    }
    catch {
        # Feature directory may be missing entirely; fall through to the ledger.
    }

    if ($LedgerEntry -and
        $LedgerEntry.PSObject.Properties['featureSource'] -and
        -not [string]::IsNullOrWhiteSpace([string]$LedgerEntry.featureSource) -and
        (Test-Path -LiteralPath $LedgerEntry.featureSource)) {
        return Read-FeatureManifest -Path $LedgerEntry.featureSource
    }

    throw "Manifest for feature '$Id' not found in the feature directory or in the ledger."
}
