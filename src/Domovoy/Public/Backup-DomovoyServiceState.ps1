function Backup-DomovoyServiceState {
    <#
    .SYNOPSIS
    Exports the full service table (name, display name, status, startup type)
    to a JSON file. Read-only for the system (catalog #8).

    .DESCRIPTION
    The file lands in <store>\backups\services-<timestamp>.json unless an
    explicit -OutputPath is given. This is the Domovoy answer to the export
    ideas of Modern Tweaker (2.0 Exportext / 3.0 Exportdrv): a plain,
    inspectable JSON snapshot, not a black box.

    .PARAMETER OutputPath
    Explicit output file path. Defaults to the store backups directory.

    .EXAMPLE
    Backup-DomovoyServiceState
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string]$OutputPath
    )

    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
        $OutputPath = Get-DomovoyStorePath -SubPath ("backups/services-{0}.json" -f $stamp)
    }

    $module = Get-Module -Name Domovoy
    $version = if ($module) { $module.Version.ToString() } else { 'unknown' }

    $services = @(Get-Service | Sort-Object -Property Name |
        Select-Object Name, DisplayName, Status, StartType)

    $payload = [pscustomobject]@{
        schema = 1
        tool = 'Domovoy'
        toolVersion = $version
        timestamp = (Get-Date).ToString('o')
        count = $services.Count
        services = $services
    }

    $payload | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $OutputPath -Encoding UTF8

    [pscustomobject]@{
        File = $OutputPath
        Services = $services.Count
    }
}
