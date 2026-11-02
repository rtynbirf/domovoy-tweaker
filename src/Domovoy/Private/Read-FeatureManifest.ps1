function Read-FeatureManifest {
    <#
    .SYNOPSIS
    Reads and validates a feature manifest JSON file.

    .NOTES
    A manifest missing any required field, or without ops/verify, is rejected
    before it can ever touch the system (invariant I7).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Manifest not found: $Path"
    }

    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $manifest = $raw | ConvertFrom-Json

    foreach ($field in @('id', 'title', 'version', 'category', 'risk', 'description', 'ops', 'undo', 'verify', 'references')) {
        if (-not $manifest.PSObject.Properties[$field]) {
            throw ("Manifest '{0}' is missing required field: {1}" -f $Path, $field)
        }
    }

    if (@($manifest.ops).Count -eq 0) {
        throw ("Manifest '{0}' contains no ops." -f $Path)
    }

    if (@($manifest.verify).Count -eq 0) {
        throw ("Manifest '{0}' contains no verify probes." -f $Path)
    }

    if ($manifest.undo.mode -ne 'snapshot') {
        throw ("Manifest '{0}': unsupported undo mode '{1}'." -f $Path, $manifest.undo.mode)
    }

    return $manifest
}
