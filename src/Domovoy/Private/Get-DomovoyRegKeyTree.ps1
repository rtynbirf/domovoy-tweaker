function Get-DomovoyRegKeyTree {
    <#
    .SYNOPSIS
    Captures a registry key subtree exactly: every value with its kind and
    data, recursively through every subkey.

    .DESCRIPTION
    Catalog 81 groundwork: undo must restore a shell handler registration
    exactly, not approximately. The capture uses DoNotExpandEnvironmentNames
    so an ExpandString value comes back unexpanded, Binary data is stored as
    base64 (the ledger is JSONL) and MultiString stays an array. A missing
    key is a $null answer, not an error.

    .PARAMETER Path
    Registry path in the provider spelling, for example
    'HKCU:\Software\Classes\*\shellex\ContextMenuHandlers\SomeHandler'.

    .EXAMPLE
    Get-DomovoyRegKeyTree -Path 'HKCU:\Software\Classes\DomovoyTest\shellex'
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    $item = Get-Item -LiteralPath $Path -ErrorAction Stop
    $values = @()
    foreach ($valueName in @($item.GetValueNames())) {
        $kind = [string]$item.GetValueKind($valueName)
        $raw = $item.GetValue($valueName, $null,
            [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        $data = $raw
        if ($kind -eq 'Binary') {
            if ($null -eq $raw) { $data = '' }
            else { $data = [Convert]::ToBase64String([byte[]]$raw) }
        }
        $values += @{
            name = [string]$valueName
            kind = $kind
            data = $data
        }
    }

    $subkeys = @()
    foreach ($childName in @($item.GetSubKeyNames())) {
        $childPath = Join-Path -Path $Path -ChildPath $childName
        $childTree = Get-DomovoyRegKeyTree -Path $childPath
        if ($null -ne $childTree) {
            $subkeys += $childTree
        }
    }

    @{
        name    = $item.PSChildName
        values  = @($values)
        subkeys = @($subkeys)
    }
}
