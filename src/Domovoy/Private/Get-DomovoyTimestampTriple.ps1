function Get-DomovoyTimestampTriple {
    <#
    .SYNOPSIS
    Reads the three filesystem timestamps of one path as ISO strings.
    .DESCRIPTION
    Catalog 91 helper: one spelling everywhere (plan, snapshot, probe, undo)
    - UTC, round-trip 'o' format, '<missing>' when the path does not exist.
    -Force: a Hidden file is invisible to Get-Item without it (the file
    .attribute lesson).
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return @{ creation = '<missing>'; lastWrite = '<missing>'; lastAccess = '<missing>' }
    }

    $item = Get-Item -LiteralPath $Path -Force
    $invariant = [System.Globalization.CultureInfo]::InvariantCulture
    return @{
        creation   = $item.CreationTimeUtc.ToString('o', $invariant)
        lastWrite  = $item.LastWriteTimeUtc.ToString('o', $invariant)
        lastAccess = $item.LastAccessTimeUtc.ToString('o', $invariant)
    }
}
