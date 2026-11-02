function Get-DomovoyGroupResolutionOrder {
    <#
    .SYNOPSIS
    Resolves the group dependency graph into an ordered list (dependencies
    before dependents). Private helper of Invoke-DomovoyGroup.

    .DESCRIPTION
    Post-order depth-first traversal. State travels through parameters and
    return values, not through shared script variables. The Done hashtable
    is a reference type: it is filled once per top-level call and prevents
    diamond dependencies from being added twice. The cycle check runs BEFORE
    the Done check - a cycle must be reported, not silently swallowed by the
    memo.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$RootId,

        [hashtable]$Done = @{},

        [string[]]$Path = @()
    )

    if (@($Path) -contains $RootId) {
        $chain = (@($Path) + $RootId) -join ' -> '
        throw "Group dependency cycle detected: $chain"
    }
    if ($Done.ContainsKey($RootId)) {
        return @()
    }

    $definition = @(Get-DomovoyGroup -Id $RootId)
    if ($definition.Count -eq 0) {
        $requirer = if (@($Path).Count -gt 0) { @($Path)[-1] } else { '<request>' }
        throw ("Dependency group not found: '{0}' (required by '{1}')." -f $RootId, $requirer)
    }

    $result = @()
    foreach ($dependency in @($definition[0].DependsOn)) {
        $result += Get-DomovoyGroupResolutionOrder -RootId $dependency -Done $Done -Path (@($Path) + $RootId)
    }

    $Done[$RootId] = $true
    $result += $definition[0]
    return $result
}
