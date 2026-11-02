function Restore-DomovoyRegKeyTree {
    <#
    .SYNOPSIS
    Recreates a registry key subtree captured by Get-DomovoyRegKeyTree.

    .DESCRIPTION
    The exact counterpart of the capture: creates the key under ParentPath,
    writes every value with its exact kind (Binary from base64, MultiString
    as a string array, DWord/QWord through the .NET provider so the numeric
    spelling survives the JSONL round trip), then recurses into subkeys.
    Used by undo for shell handler registrations (catalog 81).

    .PARAMETER Tree
    A node as returned by Get-DomovoyRegKeyTree (hashtable or the
    PSCustomObject it becomes after a ledger round trip).

    .PARAMETER ParentPath
    Registry path the captured key is recreated under.

    .EXAMPLE
    Restore-DomovoyRegKeyTree -Tree $tree -ParentPath 'HKCU:\Software\Classes\DomovoyTest\shellex\ContextMenuHandlers'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Tree,

        [Parameter(Mandatory)]
        [string]$ParentPath
    )

    if ($null -eq $Tree) { return }

    $name = [string]$Tree.name
    $keyPath = Join-Path -Path $ParentPath -ChildPath $name
    $null = New-Item -Path $keyPath -ItemType Directory -Force
    $item = Get-Item -LiteralPath $keyPath -ErrorAction Stop

    foreach ($value in @($Tree.values)) {
        $kindName = [string]$value.kind
        $kind = [Microsoft.Win32.RegistryValueKind]::String
        if (-not [Enum]::TryParse([Microsoft.Win32.RegistryValueKind], $kindName, $true, [ref]$kind)) {
            $kind = [Microsoft.Win32.RegistryValueKind]::String
        }
        $data = $value.data
        switch ($kind.ToString()) {
            'Binary' {
                $data = [Convert]::FromBase64String([string]$data)
            }
            'MultiString' {
                if ($null -eq $data) { $data = @() }
                else { $data = [string[]]@($data | ForEach-Object { [string]$_ }) }
            }
            'DWord' { $data = [int]$data }
            'QWord' { $data = [long]$data }
            default { $data = [string]$data }
        }
        $item.SetValue([string]$value.name, $data, $kind)
    }

    foreach ($child in @($Tree.subkeys)) {
        Restore-DomovoyRegKeyTree -Tree $child -ParentPath $keyPath
    }
}
