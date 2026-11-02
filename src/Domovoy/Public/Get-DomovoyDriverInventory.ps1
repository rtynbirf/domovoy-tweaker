function Get-DomovoyDriverInventory {
    <#
    .SYNOPSIS
    Lists installed device drivers; optionally exports the full table as a
    JSON snapshot into the Domovoy store. Read-only, changes nothing.

    .DESCRIPTION
    Catalog features 45 (inventory) and 42 (batch export). The inventory is
    the half that was always missing in the "export drivers" tools: before
    exporting anything you can see what is actually installed. With -Export
    the complete table is written to the store as drivers-<timestamp>.json
    (catalog feature 42), so two exports can be compared later.

    .PARAMETER Export
    Also write the full table to the Domovoy store as a JSON snapshot.

    .EXAMPLE
    Get-DomovoyDriverInventory

    .EXAMPLE
    Get-DomovoyDriverInventory -Export
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [switch]$Export
    )

    $drivers = @(
        Get-CimInstance -ClassName Win32_PnPSignedDriver -ErrorAction Stop |
            Where-Object { $_.DeviceName } |
            Select-Object -Property DeviceName, DriverVersion, DriverDate,
                DriverProviderName, IsSigned, DriverSignerName, InfName
    )

    if ($Export) {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $file = Get-DomovoyStorePath -SubPath ('drivers-{0}.json' -f $stamp)
        $payload = [ordered]@{
            exportedAt = [DateTimeOffset]::UtcNow.ToString('o')
            count = @($drivers).Count
            drivers = $drivers
        }
        $payload | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $file -Encoding UTF8

        [pscustomobject]@{
            Count = @($drivers).Count
            ExportedTo = $file
        }
        return
    }

    return $drivers
}
