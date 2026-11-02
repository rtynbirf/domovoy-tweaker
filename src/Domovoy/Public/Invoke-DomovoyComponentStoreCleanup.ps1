function Invoke-DomovoyComponentStoreCleanup {
    <#
    .SYNOPSIS
    Measures the component store (dry-run by default) or triggers Windows'
    own StartComponentCleanup maintenance task.

    .DESCRIPTION
    Catalog feature 88: Component Store cleanup with a backup gate. Domovoy
    never deletes anything from WinSxS itself and never uses the ResetBase
    switch: with -Apply the command only triggers the documented built-in
    scheduled task \Microsoft\Windows\Servicing\StartComponentCleanup, which
    is Windows' own servicing maintenance path (it removes superseded
    components and keeps the ability to uninstall updates).

    The backup gate, in the spirit of the driver dedup (catalog 43): the
    dry-run is the default and shows the measured WinSxS size and the task
    state; -Apply requires elevation, attempts a system restore point first
    and refuses to trigger anything if the servicing task is missing. The
    fact of the trigger is appended to the ledger as a componentstore.apply
    event.

    .EXAMPLE
    Invoke-DomovoyComponentStoreCleanup

    .EXAMPLE
    Invoke-DomovoyComponentStoreCleanup -Apply
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [switch]$Apply,

        [switch]$SkipRestorePoint
    )

    $taskPath = '\Microsoft\Windows\Servicing\'
    $taskName = 'StartComponentCleanup'
    $winSxs = Join-Path -Path $env:SystemRoot -ChildPath 'WinSxS'

    # The measured size is the honest part of the report: a real number, not
    # an estimate copied from a blog post.
    $bytes = [long]0
    $files = 0
    if (Test-Path -LiteralPath $winSxs) {
        $entries = @(Get-ChildItem -LiteralPath $winSxs -Recurse -File -Force -ErrorAction SilentlyContinue)
        $files = @($entries).Count
        $measure = $entries | Measure-Object -Property Length -Sum
        if ($measure.Sum) { $bytes = [long]$measure.Sum }
    }
    if (-not $bytes) { $bytes = [long]0 }

    $task = Get-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction SilentlyContinue
    $taskState = if ($task) { [string]$task.State } else { '<missing>' }

    if (-not $Apply) {
        [pscustomobject]@{
            Mode = 'DryRun'
            WinSxSBytes = $bytes
            WinSxSFiles = $files
            TaskPath = $taskPath
            TaskName = $taskName
            TaskState = $taskState
            Note = 'With -Apply Domovoy triggers the built-in StartComponentCleanup task only; it deletes nothing itself and never uses ResetBase.'
        }
        return
    }

    # Elevation is checked explicitly (invariant I5).
    if (-not (Test-DomovoyAdmin)) {
        throw 'Applying the component store cleanup requires an elevated PowerShell session.'
    }

    if ($taskState -eq '<missing>') {
        # The backup gate, honestly: without the servicing task there is no
        # documented Windows-owned path to run, so nothing is triggered.
        throw ('The {0}{1} task was not found on this machine; nothing was triggered.' -f $taskPath, $taskName)
    }

    if ($PSCmdlet.ShouldProcess("$taskPath$taskName", 'Trigger the built-in component store cleanup task')) {
        # System restore point (soft: Windows allows one per 24h).
        if (-not $SkipRestorePoint) {
            try {
                New-DomovoyRestorePoint -Description 'Domovoy: component store cleanup' -ErrorAction Stop | Out-Null
            }
            catch {
                Write-Verbose ("Restore point was not created: {0}" -f $_.Exception.Message)
            }
        }

        $null = Start-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction Stop

        $written = Write-DomovoyLedgerEntry -Entry @{
            event = 'componentstore.apply'
            target = "$taskPath$taskName"
            winSxsBytes = $bytes
            winSxsFiles = $files
        }

        [pscustomobject]@{
            Mode = 'Apply'
            Triggered = $true
            TaskPath = $taskPath
            TaskName = $taskName
            WinSxSBytes = $bytes
            LedgerTimestamp = $written['timestamp']
            Note = 'The task runs asynchronously: check the freed space later with a new dry-run.'
        }
    }
}
