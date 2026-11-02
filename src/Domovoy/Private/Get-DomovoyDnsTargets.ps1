function Get-DomovoyDnsTargets {
    <#
    .SYNOPSIS
    Resolves the interface alias selector of a network.dns operation or probe
    into a concrete list of adapter aliases.

    .NOTES
    The wildcard selector '*' means every physical adapter that is currently
    up. A literal alias is returned unchanged - a missing adapter is an
    honest, verifiable '<missing>' result downstream, not an error here.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [string]$InterfaceAlias
    )

    $selector = $InterfaceAlias
    if ([string]::IsNullOrWhiteSpace($selector)) {
        $selector = '*'
    }

    if ($selector -ne '*') {
        return @($selector)
    }

    $adapters = @(Get-NetAdapter -ErrorAction SilentlyContinue |
        Where-Object { $_.Status -eq 'Up' } |
        Select-Object -ExpandProperty Name -Unique | Sort-Object)

    return $adapters
}
