function Get-DomovoyFeature {
    <#
    .SYNOPSIS
    Lists Domovoy features declared by manifests.

    .DESCRIPTION
    Reads JSON manifests from the feature directory and returns one record per
    feature. Manifests are validated before being listed (invariant I7).

    .PARAMETER Id
    Filter by exact feature id.

    .PARAMETER Path
    Explicit feature directory. Defaults to $env:DOMOVOY_FEATURES_DIR, then to
    the repository config/features folder relative to the module.

    .EXAMPLE
    Get-DomovoyFeature

    .EXAMPLE
    Get-DomovoyFeature -Id services.diagtrack.disabled
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Position = 0)]
        [string]$Id,

        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        if (-not [string]::IsNullOrWhiteSpace($env:DOMOVOY_FEATURES_DIR)) {
            $Path = $env:DOMOVOY_FEATURES_DIR
        }
        else {
            $module = Get-Module -Name Domovoy
            if (-not $module) {
                throw 'Domovoy module is not imported.'
            }
            $repoRoot = Split-Path -Parent (Split-Path -Parent $module.ModuleBase)
            $Path = Join-Path -Path $repoRoot -ChildPath 'config/features'
            if (-not (Test-Path -LiteralPath $Path)) {
                $Path = Join-Path -Path $module.ModuleBase -ChildPath 'config/features'
            }
        }
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Feature directory not found: $Path"
    }

    $items = @()
    $files = Get-ChildItem -LiteralPath $Path -Filter '*.json' | Sort-Object -Property Name
    foreach ($file in $files) {
        $manifest = Read-FeatureManifest -Path $file.FullName
        if (-not [string]::IsNullOrEmpty($Id) -and $manifest.id -ne $Id) {
            continue
        }
        $items += [pscustomobject]@{
            Id = $manifest.id
            Title = $manifest.title
            Version = $manifest.version
            Category = $manifest.category
            Risk = $manifest.risk
            OpCount = @($manifest.ops).Count
            File = $file.FullName
        }
    }

    return $items
}
