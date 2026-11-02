function Undo-DomovoyFileAttributeClear {
    <#
    .SYNOPSIS
    Restores the exact previous attributes captured by the newest
    fileattr.clear ledger event (dry-run by default).

    .DESCRIPTION
    Catalog feature 47, the undo half: every path from the newest
    Invoke-DomovoyFileAttributeClear -Apply gets its full previous attribute
    set back from the ledger snapshot. A path deleted since the change is
    skipped and reported honestly.

    .EXAMPLE
    Undo-DomovoyFileAttributeClear

    .EXAMPLE
    Undo-DomovoyFileAttributeClear -Apply
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [switch]$Apply
    )

    $event = @(Get-DomovoyLedger -Event 'fileattr.clear' -Last 1000000) |
        Select-Object -Last 1

    if (-not $event) {
        throw 'No attribute clearing found in the ledger. Nothing to undo.'
    }

    $plan = @()
    foreach ($entry in @($event.snapshot)) {
        $exists = Test-Path -LiteralPath $entry.path
        $plan += [pscustomobject]@{
            Path = $entry.path
            Exists = $exists
            WouldRestoreTo = $entry.previousAttributes
        }
    }

    # Dry-run by default (invariant I3).
    if (-not $Apply) {
        [pscustomobject]@{
            Mode = 'DryRun'
            ChangedAt = $event.timestamp
            Plan = $plan
        }
        return
    }

    if ($PSCmdlet.ShouldProcess(($plan.Path -join ', '), 'Restore previous file attributes')) {
        $restored = 0
        $skipped = 0
        foreach ($entry in @($event.snapshot)) {
            if (-not (Test-Path -LiteralPath $entry.path)) {
                $skipped++
                continue
            }
            # -Force: the file may carry Hidden until the restore below runs.
            $item = Get-Item -LiteralPath $entry.path -Force
            $target = [System.IO.FileAttributes]$entry.previousAttributes
            if ($item.Attributes -band [System.IO.FileAttributes]::Directory) {
                # The Directory bit itself cannot be cleared; keep it.
                $target = $target -bor [System.IO.FileAttributes]::Directory
            }
            $item.Attributes = $target
            $restored++
        }

        $written = Write-DomovoyLedgerEntry -Entry @{
            event = 'fileattr.clear.undo'
            restored = $restored
            skipped = $skipped
            changedAt = $event.timestamp
        }

        [pscustomobject]@{
            Mode = 'Undo'
            Restored = $restored
            Skipped = $skipped
            LedgerTimestamp = $written['timestamp']
        }
    }
}
