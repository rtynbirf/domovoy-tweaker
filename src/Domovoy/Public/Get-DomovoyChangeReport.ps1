function Get-DomovoyChangeReport {
    <#
    .SYNOPSIS
    Summarizes everything Domovoy changed since a given moment, from the
    ledger, with dates. Read-only, changes nothing.

    .DESCRIPTION
    Catalog feature 63: "what changed since X" must answer from the journal,
    not from memory. The report walks every ledger event (apply, undo,
    cleanup, network reset, memory trim, integrity check) that happened at or
    after -Since and builds one row per event with a human summary.

    .PARAMETER Since
    Only include events at or after this moment. Default: everything.

    .PARAMETER Last
    Maximum number of ledger entries to walk (most recent last).

    .EXAMPLE
    Get-DomovoyChangeReport -Since (Get-Date).AddDays(-7)
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [datetime]$Since,

        [ValidateRange(1, 1000000)]
        [int]$Last = 1000000
    )

    $entries = @(Get-DomovoyLedger -Last $Last)

    if ($PSBoundParameters.ContainsKey('Since')) {
        $sinceOffset = [DateTimeOffset]$Since
        $entries = @($entries | Where-Object { [DateTimeOffset]$_.timestamp -ge $sinceOffset })
    }

    $rows = @()
    foreach ($entry in $entries) {
        $summary = switch ($entry.event) {
            'ledger.init' { 'store initialized' }
            'feature.apply' {
                $pass = '<unknown>'
                if ($entry.PSObject.Properties['verification'] -and $entry.verification) {
                    $pass = [string]$entry.verification.AllPass
                }
                'feature applied, verified: {0}' -f $pass
            }
            'feature.undo' { 'feature undone from snapshot' }
            'cleanup.apply' {
                'cleanup: {0} files, {1} bytes freed, {2} failed' -f $entry.filesRemoved, $entry.bytesFreed, $entry.filesFailed
            }
            'networkreset.apply' {
                'network reset ({0}); static settings snapshot recorded' -f $entry.target
            }
            'eventlog.cleanup.apply' {
                'event logs cleared: {0} entries -> {1} entries' -f $entry.entriesBefore, $entry.entriesAfter
            }
            'memorytrim.apply' {
                'memory trim: {0} processes, {1} bytes before, {2} bytes after' -f $entry.processes, $entry.bytesBefore, $entry.bytesAfter
            }
            'integritycheck.apply' {
                'integrity check ({0}) exit code {1}' -f $entry.tool, $entry.exitCode
            }
            default { 'event' }
        }

        $rows += [pscustomobject]@{
            Timestamp = $entry.timestamp
            Event = $entry.event
            FeatureId = $entry.featureId
            Summary = $summary
        }
    }

    $counts = @{}
    foreach ($row in $rows) {
        if ($counts.ContainsKey($row.Event)) {
            $counts[$row.Event]++
        }
        else {
            $counts[$row.Event] = 1
        }
    }

    [pscustomobject]@{
        Since = if ($PSBoundParameters.ContainsKey('Since')) { [DateTimeOffset]$Since } else { $null }
        Events = $rows.Count
        Counts = $counts
        Report = $rows
    }
}
