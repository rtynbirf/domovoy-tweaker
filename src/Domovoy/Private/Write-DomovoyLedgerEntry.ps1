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
    $Entry['toolVersion'] = '0.1.0'
    $Entry['timestamp'] = [DateTimeOffset]::UtcNow.ToString('o')

    $line = $Entry | ConvertTo-Json -Depth 12 -Compress
    Add-Content -LiteralPath $ledgerPath -Value $line -Encoding UTF8

    return $Entry
}
