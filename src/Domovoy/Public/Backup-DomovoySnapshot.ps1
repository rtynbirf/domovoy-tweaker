function Backup-DomovoySnapshot {
    <#
    .SYNOPSIS
    Captures an explicit snapshot of the state a feature is going to touch.

    .DESCRIPTION
    Reads the feature manifest and stores the current registry values (with
    types) and service startup types into snapshots/<featureId>/<timestamp>.json
    without changing anything.

    .EXAMPLE
    Backup-DomovoySnapshot -Id services.diagtrack.disabled
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$Id
    )

    $feature = Get-DomovoyFeature -Id $Id
    if (-not $feature) {
        throw "Feature not found: $Id"
    }
    $manifest = Read-FeatureManifest -Path $feature[0].File

    $snapshot = @()
    foreach ($op in @($manifest.ops)) {
        switch ($op.type) {
            'registry.set' {
                $kind = 'None'
                $value = '<unset>'
                if (Test-Path -LiteralPath $op.path) {
                    try {
                        $property = Get-ItemProperty -LiteralPath $op.path -Name $op.name -ErrorAction Stop
                        $value = [string]$property.($op.name)
                    }
                    catch {
                        $value = '<unset>'
                    }
                    try {
                        $kind = [string](Get-Item -LiteralPath $op.path -ErrorAction Stop).GetValueKind($op.name)
                    }
                    catch {
                        $kind = 'None'
                    }
                }
                $snapshot += @{
                    op = 'registry.set'
                    path = $op.path
                    name = $op.name
                    previousValue = $value
                    previousType = $kind
                }
            }
            'service.startup' {
                $service = Get-Service -Name $op.name -ErrorAction SilentlyContinue
                $snapshot += @{
                    op = 'service.startup'
                    name = $op.name
                    previousValue = if ($service) { [string]$service.StartType } else { '<missing>' }
                }
            }
        }
    }

    $safeId = $Id -replace '[^A-Za-z0-9._-]', '_'
    $file = Get-DomovoyStorePath -SubPath ('snapshots/{0}/{1}.json' -f $safeId, (Get-Date).ToString('yyyyMMdd-HHmmss'))

    $snapshot | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $file -Encoding UTF8

    [pscustomobject]@{
        Feature = $Id
        File = $file
        Entries = @($snapshot).Count
    }
}
