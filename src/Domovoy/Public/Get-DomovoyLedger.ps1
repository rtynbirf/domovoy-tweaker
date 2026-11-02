function Get-DomovoyLedger {
    <#
    .SYNOPSIS
    Reads entries from the Domovoy ledger.

    .PARAMETER FeatureId
    Filter by feature id.

    .PARAMETER Event
    Filter by event type; 'all' returns everything.

    .PARAMETER Last
    Maximum number of entries to return (most recent last).

    .EXAMPLE
    Get-DomovoyLedger

    .EXAMPLE
    Get-DomovoyLedger -FeatureId services.diagtrack.disabled -Event feature.apply
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string]$FeatureId,

        [ValidateSet('ledger.init', 'feature.apply', 'feature.undo', 'cleanup.apply', 'networkreset.apply', 'eventlog.cleanup.apply', 'memorytrim.apply', 'integritycheck.apply', 'autoheal.cycle', 'watchdog.register', 'watchdog.unregister', 'driverdedup.apply', 'fileattr.clear', 'fileattr.clear.undo', 'fileowner.set', 'fileowner.undo', 'privilege.enable', 'privilege.disable', 'bitlocker.keybackup', 'componentstore.apply', 'group.apply', 'ledger.migrate', 'all')]
        [string]$Event = 'all',

        [ValidateRange(1, 1000000)]
        [int]$Last = 50
    )

    $ledgerPath = Get-DomovoyStorePath -SubPath 'ledger.jsonl'
    if (-not (Test-Path -LiteralPath $ledgerPath)) {
        return @()
    }

    $entries = @()
    $lines = Get-Content -LiteralPath $ledgerPath -Encoding UTF8
    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }
        try {
            $entries += ($line | ConvertFrom-Json)
        }
        catch {
            # A torn line must not destroy the whole ledger history (spec 6.1).
            continue
        }
    }

    if (-not [string]::IsNullOrEmpty($FeatureId)) {
        $entries = @($entries | Where-Object { $_.featureId -eq $FeatureId })
    }

    if ($Event -ne 'all') {
        $entries = @($entries | Where-Object { $_.event -eq $Event })
    }

    return @($entries | Select-Object -Last $Last)
}
