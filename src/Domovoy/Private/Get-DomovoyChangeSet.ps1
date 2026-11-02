function Get-DomovoyChangeSet {
    <#
    .SYNOPSIS
    Builds the "what actually changed" rows: snapshot before apply vs probe
    results after apply.

    .DESCRIPTION
    Catalog feature direction "what really changed" (v0.5): a tweak report
    must show measured reality, not the plan. The before value comes from the
    snapshot captured right before the first operation (invariant I2); the
    after value comes from the verification probes run right after the last
    one. Each op type stores the previous state under its own field name, so
    the op-to-probe mapping is explicit here.

    .PARAMETER Manifest
    The feature manifest that was applied (links ops to probes).

    .PARAMETER Snapshot
    The snapshot array recorded in the ledger feature.apply event.

    .PARAMETER Verification
    The Test-DomovoyEffect result recorded after apply.

    .EXAMPLE
    Get-DomovoyChangeSet -Manifest $m -Snapshot $snapshot -Verification $v
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [psobject]$Manifest,

        [AllowEmptyCollection()]
        [array]$Snapshot = @(),

        [Parameter(Mandatory)]
        [psobject]$Verification
    )

    # Snapshot values keyed exactly like the probe targets they answer for.
    $before = @{}
    foreach ($item in @($Snapshot)) {
        $key = $null
        $value = $null
        switch ($item.op) {
            'registry.set' {
                $key = 'registry.set|{0}\{1}' -f $item.path, $item.name
                $value = $item.previousValue
            }
            'registry.delete' {
                # The registry.absent probe asks the same question the
                # registry.delete snapshot answers.
                $key = 'registry.absent|{0}\{1}' -f $item.path, $item.name
                $value = $item.previousValue
            }
            'service.startup' {
                $key = 'service.startup|{0}' -f $item.name
                $value = $item.previousValue
            }
            'service.stop' {
                $key = 'service.status|{0}' -f $item.name
                $value = $item.previousStatus
            }
            'appx.remove' {
                $key = 'appx.absent|{0}' -f $item.name
                $value = if ($item.packageFullName -eq '<missing>') { '<absent>' } else { $item.packageFullName }
            }
            'file.attribute' {
                $key = 'file.attributes|{0}' -f $item.path
                $value = $item.previousAttributes
            }
            'scheduler.task' {
                $key = 'scheduler.taskState|{0}{1}' -f $item.taskPath, $item.taskName
                $value = $item.previousState
            }
        }
        if ($key) {
            $before[$key] = [string]$value
        }
    }

    $rows = @()
    foreach ($probe in @($Verification.Results)) {
        $key = '{0}|{1}' -f $probe.Probe, $probe.Target
        if ($before.ContainsKey($key)) {
            $beforeValue = $before[$key]
        }
        else {
            # No snapshot entry answered this probe (should not happen for a
            # well-formed manifest, but honesty beats silence).
            $beforeValue = '<unknown>'
        }
        $afterValue = [string]$probe.Actual
        $rows += [pscustomobject]@{
            Probe = $probe.Probe
            Target = $probe.Target
            Before = $beforeValue
            After = $afterValue
            Changed = ($beforeValue -ne $afterValue)
        }
    }

    return @($rows)
}
