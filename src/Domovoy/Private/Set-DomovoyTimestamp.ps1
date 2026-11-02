function Set-DomovoyTimestamp {
    <#
    .SYNOPSIS
    Sets one filesystem timestamp (creation, lastWrite or lastAccess) from an
    ISO 8601 string.
    .DESCRIPTION
    Catalog 91 helper. The manifest spelling is parsed with the invariant
    culture; an instant without an offset is read as UTC (AssumeUniversal).
    The value is applied as UTC, so the stored instant - not the local
    spelling - is what apply sets and undo restores. Works for files and
    directories alike (Get-Item returns FileInfo or DirectoryInfo).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [ValidateSet('creation', 'lastWrite', 'lastAccess')]
        [string]$Field,

        [Parameter(Mandatory)]
        [string]$Value
    )

    $item = Get-Item -LiteralPath $Path -Force
    $instant = [DateTimeOffset]::Parse(
        $Value,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::AssumeUniversal)

    switch ($Field) {
        'creation'   { $item.CreationTimeUtc   = $instant.UtcDateTime }
        'lastWrite'  { $item.LastWriteTimeUtc  = $instant.UtcDateTime }
        'lastAccess' { $item.LastAccessTimeUtc = $instant.UtcDateTime }
    }
}
