function Invoke-DomovoyEventLogCleanup {
    <#
    .SYNOPSIS
    Shows how many records the Windows event logs hold (dry-run by default)
    or clears them, recording the fact in the ledger.

    .DESCRIPTION
    Catalog feature 38: in the case-study tools event logs were "cleaned
    quietly"; here the cleanup itself becomes a recorded event. The report
    first: log names, record counts before, record counts after (measured
    again after clearing, not derived). Clearing requires -Apply, elevation
    and appends an eventlog.cleanup.apply event with both numbers to the
    ledger. Logs that cannot be cleared are counted honestly as failed.

    .PARAMETER LogName
    Clear only these logs. Default: every log that currently holds records.

    .PARAMETER Apply
    Perform the clearing. Without this switch only the report is shown.

    .EXAMPLE
    Invoke-DomovoyEventLogCleanup

    .EXAMPLE
    Invoke-DomovoyEventLogCleanup -LogName System -Apply
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [string[]]$LogName,

        [switch]$Apply
    )

    if ($LogName) {
        $logs = @(Get-WinEvent -ListLog $LogName -ErrorAction SilentlyContinue)
    }
    else {
        $logs = @(Get-WinEvent -ListLog * -ErrorAction SilentlyContinue |
            Where-Object { $_.RecordCount -gt 0 })
    }

    $entriesBefore = [long]0
    foreach ($log in $logs) {
        if ($log.RecordCount -gt 0) {
            $entriesBefore += [long]$log.RecordCount
        }
    }

    if (-not $Apply) {
        $rows = @()
        foreach ($log in $logs) {
            $rows += [pscustomobject]@{
                LogName = $log.LogName
                RecordCount = $log.RecordCount
                FileSizeBytes = $log.FileSize
            }
        }
        [pscustomobject]@{
            Mode = 'DryRun'
            Logs = $rows.Count
            EntriesBefore = $entriesBefore
            Report = $rows
        }
        return
    }

    if (-not (Test-DomovoyAdmin)) {
        throw 'Clearing event logs requires an elevated PowerShell session.'
    }

    if ($PSCmdlet.ShouldProcess(($logs.LogName -join '; '), 'Clear Windows event logs')) {
        $cleared = 0
        $failed = 0
        $failedNames = @()
        foreach ($log in $logs) {
            try {
                Clear-EventLog -LogName $log.LogName -ErrorAction Stop
                $cleared++
            }
            catch {
                $failed++
                $failedNames += $log.LogName
            }
        }

        # Measured "after": re-read the record counts, do not derive them.
        $entriesAfter = [long]0
        foreach ($log in @(Get-WinEvent -ListLog $logs.LogName -ErrorAction SilentlyContinue)) {
            if ($log.RecordCount -gt 0) {
                $entriesAfter += [long]$log.RecordCount
            }
        }

        $written = Write-DomovoyLedgerEntry -Entry @{
            event = 'eventlog.cleanup.apply'
            featureId = 'eventlog.cleanup'
            logsCleared = $cleared
            logsFailed = $failed
            failedLogs = $failedNames
            entriesBefore = $entriesBefore
            entriesAfter = $entriesAfter
            irreversible = $true
        }

        [pscustomobject]@{
            Mode = 'Apply'
            LogsCleared = $cleared
            LogsFailed = $failed
            EntriesBefore = $entriesBefore
            EntriesAfter = $entriesAfter
            LedgerTimestamp = $written['timestamp']
        }
    }
}
