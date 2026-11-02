function Backup-DomovoyTaskState {
    <#
    .SYNOPSIS
    Exports the scheduled task table (path, name, state) to a JSON file.
    Read-only for the system (catalog #66).

    .DESCRIPTION
    The companion of Backup-DomovoyServiceState for the Task Scheduler: a
    plain, inspectable JSON snapshot of every task the current user can see,
    with its current state. Domovoy never deletes task definitions (the
    scheduler.task op only toggles the state), and this command changes
    nothing at all.

    The file lands in <store>\backups\tasks-<timestamp>.json unless an
    explicit -OutputPath is given.

    .PARAMETER OutputPath
    Explicit output file path. Defaults to the store backups directory.

    .EXAMPLE
    Backup-DomovoyTaskState

    .EXAMPLE
    Backup-DomovoyTaskState -OutputPath D:\snapshots\tasks.json
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string]$OutputPath
    )

    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
        $OutputPath = Get-DomovoyStorePath -SubPath ("backups/tasks-{0}.json" -f $stamp)
    }

    $module = Get-Module -Name Domovoy
    $version = if ($module) { $module.Version.ToString() } else { 'unknown' }

    $tasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue |
        Sort-Object -Property TaskPath, TaskName |
        Select-Object TaskPath, TaskName, State)

    $payload = [pscustomobject]@{
        schema = 1
        kind = 'domovoy-task-state'
        tool = 'Domovoy'
        toolVersion = $version
        timestamp = (Get-Date).ToString('o')
        count = $tasks.Count
        tasks = $tasks
    }

    $payload | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $OutputPath -Encoding UTF8

    [pscustomobject]@{
        File = $OutputPath
        Tasks = $tasks.Count
    }
}
