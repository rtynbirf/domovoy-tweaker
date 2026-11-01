function Get-DomovoyStorePath {
    <#
    .SYNOPSIS
    Returns the Domovoy store root or a path inside it, creating directories on demand.

    .NOTES
    The store root is $env:DOMOVOY_STORE when set (tests, CI), otherwise %ProgramData%\Domovoy.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$SubPath
    )

    $root = $env:DOMOVOY_STORE
    if ([string]::IsNullOrWhiteSpace($root)) {
        $root = Join-Path -Path $env:ProgramData -ChildPath 'Domovoy'
    }

    if (-not (Test-Path -LiteralPath $root)) {
        $null = New-Item -Path $root -ItemType Directory -Force
    }

    if (-not [string]::IsNullOrWhiteSpace($SubPath)) {
        $result = Join-Path -Path $root -ChildPath $SubPath
        $parent = Split-Path -Parent $result
        if (-not [string]::IsNullOrEmpty($parent) -and -not (Test-Path -LiteralPath $parent)) {
            $null = New-Item -Path $parent -ItemType Directory -Force
        }
        return $result
    }

    return $root
}
