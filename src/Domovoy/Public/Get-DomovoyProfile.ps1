function Get-DomovoyProfile {
    <#
    .SYNOPSIS
    Lists Domovoy profiles declared as JSON bundles of feature ids.

    .DESCRIPTION
    A profile is JSON, not a script (roadmap v0.3 acceptance criterion). Each
    profile declares a risk ceiling (maxRisk); features above the ceiling are
    skipped by Invoke-DomovoyProfile and reported honestly.

    .PARAMETER Id
    Filter by exact profile id.

    .PARAMETER Path
    Explicit profile directory. Defaults to $env:DOMOVOY_PROFILES_DIR, then to
    the repository config/profiles folder relative to the module.

    .EXAMPLE
    Get-DomovoyProfile

    .EXAMPLE
    Get-DomovoyProfile -Id cautious
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Position = 0)]
        [string]$Id,

        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        if (-not [string]::IsNullOrWhiteSpace($env:DOMOVOY_PROFILES_DIR)) {
            $Path = $env:DOMOVOY_PROFILES_DIR
        }
        else {
            $module = Get-Module -Name Domovoy
            if (-not $module) {
                throw 'Domovoy module is not imported.'
            }
            $repoRoot = Split-Path -Parent (Split-Path -Parent $module.ModuleBase)
            $Path = Join-Path -Path $repoRoot -ChildPath 'config/profiles'
            if (-not (Test-Path -LiteralPath $Path)) {
                $Path = Join-Path -Path $module.ModuleBase -ChildPath 'config/profiles'
            }
        }
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Profile directory not found: $Path"
    }

    $items = @()
    $files = Get-ChildItem -LiteralPath $Path -Filter '*.json' | Sort-Object -Property Name
    foreach ($file in $files) {
        $raw = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
        $profileDef = $raw | ConvertFrom-Json

        foreach ($field in @('id', 'title', 'maxRisk', 'description', 'features')) {
            if (-not $profileDef.PSObject.Properties[$field]) {
                throw ("Profile '{0}' is missing required field: {1}" -f $file.FullName, $field)
            }
        }

        if ($profileDef.maxRisk -notin @('low', 'medium', 'high')) {
            throw ("Profile '{0}': unsupported maxRisk '{1}'." -f $file.FullName, $profileDef.maxRisk)
        }

        if (-not [string]::IsNullOrEmpty($Id) -and $profileDef.id -ne $Id) {
            continue
        }

        $items += [pscustomobject]@{
            Id = $profileDef.id
            Title = $profileDef.title
            MaxRisk = $profileDef.maxRisk
            Description = $profileDef.description
            Features = @($profileDef.features)
            File = $file.FullName
        }
    }

    return $items
}
