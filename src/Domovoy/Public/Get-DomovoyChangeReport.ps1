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

    # v1.6 (item 6): the human summaries come from the strings table, so
    # the report speaks the active language. The event names and every
    # machine-readable field stay frozen (spec section 10).
    $s = Get-DomovoyStrings

    $rows = @()
    foreach ($entry in $entries) {
        $summary = switch ($entry.event) {
            'ledger.init' { $s.reportStoreInitialized }
            'feature.apply' {
                $pass = $s.reportUnknownPass
                if ($entry.PSObject.Properties['verification'] -and $entry.verification) {
                    $pass = [string]$entry.verification.AllPass
                }
                $s.reportFeatureApplied -f $pass
            }
            'feature.undo' { $s.reportFeatureUndone }
            'cleanup.apply' {
                $s.reportCleanup -f $entry.filesRemoved, $entry.bytesFreed, $entry.filesFailed
            }
            'networkreset.apply' {
                $s.reportNetworkReset -f $entry.target
            }
            'eventlog.cleanup.apply' {
                $s.reportEventlogCleanup -f $entry.entriesBefore, $entry.entriesAfter
            }
            'memorytrim.apply' {
                $s.reportMemoryTrim -f $entry.processes, $entry.bytesBefore, $entry.bytesAfter
            }
            'integritycheck.apply' {
                $s.reportIntegrityCheck -f $entry.tool, $entry.exitCode
            }
            default { $s.reportEventDefault }
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
