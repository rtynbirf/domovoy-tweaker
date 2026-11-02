function Unregister-DomovoyWatchdog {
    <#
    .SYNOPSIS
    Removes the opt-in drift watchdog scheduled task (dry-run by default)
    and records the fact in the ledger.

    .DESCRIPTION
    Catalog feature 58, the off switch: the \Domovoy\DriftWatchdog task is
    deleted and a watchdog.unregister event lands in the ledger. The
    generated runner script is left in the store (it is inert without the
    task and disappears with the store).

    Applying requires elevation (invariant I5).

    .EXAMPLE
    Unregister-DomovoyWatchdog

    .EXAMPLE
    Unregister-DomovoyWatchdog -Apply
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [switch]$Apply
    )

    $taskPath = '\Domovoy\'
    $taskName = 'DriftWatchdog'

    $task = Get-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction SilentlyContinue
    if (-not $task) {
        throw ("The watchdog task is not registered ({0}{1})." -f $taskPath, $taskName)
    }

    # Dry-run by default (invariant I3).
    if (-not $Apply) {
        [pscustomobject]@{
            Mode = 'DryRun'
            TaskPath = $taskPath
            TaskName = $taskName
            State = [string]$task.State
        }
        return
    }

    # Elevation is checked explicitly (invariant I5).
    if (-not (Test-DomovoyAdmin)) {
        throw 'Removing the watchdog task requires an elevated PowerShell session.'
    }

    if ($PSCmdlet.ShouldProcess("$taskPath$taskName", 'Unregister the drift watchdog scheduled task')) {
        $null = Unregister-ScheduledTask -TaskPath $taskPath -TaskName $taskName -Confirm:$false

        $written = Write-DomovoyLedgerEntry -Entry @{
            event = 'watchdog.unregister'
            taskPath = $taskPath
            taskName = $taskName
        }

        [pscustomobject]@{
            Mode = 'Apply'
            TaskPath = $taskPath
            TaskName = $taskName
            LedgerTimestamp = $written['timestamp']
        }
    }
}
