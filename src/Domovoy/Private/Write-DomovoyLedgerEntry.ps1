function Write-DomovoyLedgerEntry {
    <#
    .SYNOPSIS
    Appends one event to the Domovoy ledger (append-only JSONL, invariant I1).
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Entry
    )

    $ledgerPath = Get-DomovoyStorePath -SubPath 'ledger.jsonl'

    $Entry['schema'] = 1
    $Entry['tool'] = 'Domovoy'
    $module = Get-Module -Name Domovoy
    if ($module) {
        $Entry['toolVersion'] = $module.Version.ToString()
    }
    else {
        $Entry['toolVersion'] = 'unknown'
    }
    $Entry['timestamp'] = [DateTimeOffset]::UtcNow.ToString('o')

    $line = $Entry | ConvertTo-Json -Depth 12 -Compress
    Add-Content -LiteralPath $ledgerPath -Value $line -Encoding UTF8

    return $Entry
}
