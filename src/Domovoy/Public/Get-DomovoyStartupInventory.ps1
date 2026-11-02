function Get-DomovoyStartupInventory {
    <#
    .SYNOPSIS
    Lists the documented autostart entries (Run / RunOnce) of the current
    user and the machine. Read-only, changes nothing.

    .DESCRIPTION
    Catalog feature 41: startup management starts with an honest inventory.
    Only the documented keys are read:
    HKCU and HKLM (native plus WOW6432Node) Run and RunOnce values. To disable
    an entry later, use a manifest with the registry.delete op - Domovoy will
    snapshot and restore the exact value and type on undo.

    .EXAMPLE
    Get-DomovoyStartupInventory
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $keys = @(
        @{ Hive = 'HKCU'; Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' },
        @{ Hive = 'HKCU'; Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce' },
        @{ Hive = 'HKLM'; Path = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run' },
        @{ Hive = 'HKLM'; Path = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce' },
        @{ Hive = 'HKLM'; Path = 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run' },
        @{ Hive = 'HKLM'; Path = 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce' }
    )

    $rows = @()
    foreach ($key in $keys) {
        if (-not (Test-Path -LiteralPath $key.Path)) {
            continue
        }
        $item = Get-Item -LiteralPath $key.Path
        foreach ($valueName in $item.GetValueNames()) {
            $rows += [pscustomobject]@{
                Hive = $key.Hive
                Key = $key.Path
                Name = $valueName
                Command = [string]$item.GetValue($valueName)
            }
        }
    }

    return @($rows)
}
