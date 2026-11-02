function Get-DomovoyGroup {
    <#
    .SYNOPSIS
    Lists Domovoy feature groups: declarative packages with dependencies.

    .DESCRIPTION
    A group is JSON, not a script (same rule as profiles, roadmap v0.3). A
    group sits on top of profiles (catalog 102): it may pull whole profiles
    and single features, and may declare dependencies on other groups.
    Invoke-DomovoyGroup resolves the dependency graph and reports the
    execution order honestly.

    .PARAMETER Id
    Filter by exact group id.

    .PARAMETER Path
    Explicit group directory. Defaults to $env:DOMOVOY_GROUPS_DIR, then to
    the repository config/groups folder relative to the module.

    .EXAMPLE
    Get-DomovoyGroup

    .EXAMPLE
    Get-DomovoyGroup -Id home-essentials
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Position = 0)]
        [string]$Id,

        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        if (-not [string]::IsNullOrWhiteSpace($env:DOMOVOY_GROUPS_DIR)) {
            $Path = $env:DOMOVOY_GROUPS_DIR
        }
        else {
            $module = Get-Module -Name Domovoy
            if (-not $module) {
                throw 'Domovoy module is not imported.'
            }
            $repoRoot = Split-Path -Parent (Split-Path -Parent $module.ModuleBase)
            $Path = Join-Path -Path $repoRoot -ChildPath 'config/groups'
            if (-not (Test-Path -LiteralPath $Path)) {
                $Path = Join-Path -Path $module.ModuleBase -ChildPath 'config/groups'
            }
        }
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Group directory not found: $Path"
    }

    $items = @()
    $files = Get-ChildItem -LiteralPath $Path -Filter '*.json' | Sort-Object -Property Name
    foreach ($file in $files) {
        $raw = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
        $groupDef = $raw | ConvertFrom-Json

        foreach ($field in @('id', 'title', 'maxRisk', 'description')) {
            if (-not $groupDef.PSObject.Properties[$field]) {
                throw ("Group '{0}' is missing required field: {1}" -f $file.FullName, $field)
            }
        }

        # At least one content source: a group without content is an honest
        # error, not an empty plan.
        $hasContent = $false
        foreach ($field in @('dependsOn', 'profiles', 'features')) {
            $p = $groupDef.PSObject.Properties[$field]
            if ($p -and $null -ne $p.Value -and @($p.Value).Count -gt 0) {
                $hasContent = $true
            }
        }
        if (-not $hasContent) {
            throw ("Group '{0}' declares no dependsOn, profiles or features - nothing to resolve." -f $file.FullName)
        }

        if ($groupDef.maxRisk -notin @('low', 'medium', 'high')) {
            throw ("Group '{0}': unsupported maxRisk '{1}'." -f $file.FullName, $groupDef.maxRisk)
        }

        if (-not [string]::IsNullOrEmpty($Id) -and $groupDef.id -ne $Id) {
            continue
        }

        # An absent optional list must stay an empty array, not @($null).
        $dependsOn = @()
        $prop = $groupDef.PSObject.Properties['dependsOn']
        if ($prop -and $null -ne $prop.Value) { $dependsOn = @($prop.Value) }
        $profiles = @()
        $prop = $groupDef.PSObject.Properties['profiles']
        if ($prop -and $null -ne $prop.Value) { $profiles = @($prop.Value) }
        $features = @()
        $prop = $groupDef.PSObject.Properties['features']
        if ($prop -and $null -ne $prop.Value) { $features = @($prop.Value) }

        $items += [pscustomobject]@{
            Id          = $groupDef.id
            Title       = $groupDef.title
            MaxRisk     = $groupDef.maxRisk
            Description = $groupDef.description
            DependsOn   = $dependsOn
            Profiles    = $profiles
            Features    = $features
            File        = $file.FullName
        }
    }

    return $items
}
