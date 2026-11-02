function Get-RegistryValueSafe {
    <#
    .SYNOPSIS
    Reads a registry value as string without throwing. Returns '<unset>' when missing.

    .NOTES
    The value kind is read separately by callers that need it for snapshots.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Name
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return '<unset>'
    }

    try {
        $property = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop
        return [string]$property.($Name)
    }
    catch {
        return '<unset>'
    }
}
