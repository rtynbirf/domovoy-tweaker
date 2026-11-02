function Invoke-DomovoyMemoryTrim {
    <#
    .SYNOPSIS
    Shows the total working set (dry-run by default) or trims process working
    sets via EmptyWorkingSet, reporting measured before/after bytes.

    .DESCRIPTION
    Catalog feature 40, honestly stated: trimming is a diagnostic instrument,
    not an accelerator. Freed pages come back as soon as the processes touch
    them again; nothing is "speeded up". The command reports the measured
    total working set before and after the trim (in bytes), appends a
    memorytrim.apply event to the ledger and carries the honest note in every
    output object.

    Without -ProcessId all processes of the current user that the session can
    touch are trimmed; processes that cannot be opened are counted as skipped.

    .PARAMETER ProcessId
    Trim only this process (used by tests and for targeted diagnostics).

    .PARAMETER Apply
    Perform the trim. Without this switch only the measurement is shown.

    .EXAMPLE
    Invoke-DomovoyMemoryTrim

    .EXAMPLE
    Invoke-DomovoyMemoryTrim -ProcessId $PID -Apply
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [int]$ProcessId,

        [switch]$Apply
    )

    $honestNote = 'Trimming is temporary: freed pages return as soon as the processes use them again.'

    if (-not ([System.Management.Automation.PSTypeName]'Domovoy.Native.Memory').Type) {
        Add-Type -Namespace Domovoy.Native -Name Memory -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("psapi.dll", SetLastError = true)]
public static extern bool EmptyWorkingSet(System.IntPtr hProcess);
'@
    }

    if ($PSBoundParameters.ContainsKey('ProcessId')) {
        $targets = @(Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)
    }
    else {
        $targets = @(Get-Process -ErrorAction SilentlyContinue |
            Where-Object { $_.Path -and (-not $_.Path.StartsWith($env:SystemRoot, [System.StringComparison]::OrdinalIgnoreCase)) })
    }

    $bytesBefore = [long]0
    foreach ($proc in $targets) {
        $bytesBefore += [long]$proc.WorkingSet64
    }

    if (-not $Apply) {
        [pscustomobject]@{
            Mode = 'DryRun'
            Processes = @($targets).Count
            WorkingSetBytes = $bytesBefore
            Note = $honestNote
        }
        return
    }

    if ($PSCmdlet.ShouldProcess('process working sets', 'Trim working sets (EmptyWorkingSet)')) {
        $trimmed = 0
        $skipped = 0
        foreach ($proc in $targets) {
            try {
                $handle = $proc.Handle
                if ([Domovoy.Native.Memory]::EmptyWorkingSet($handle)) {
                    $trimmed++
                }
                else {
                    $skipped++
                }
            }
            catch {
                $skipped++
            }
        }

        # Measured after: re-read the working sets, do not derive them.
        $bytesAfter = [long]0
        foreach ($proc in $targets) {
            $refreshed = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
            if ($refreshed) {
                $bytesAfter += [long]$refreshed.WorkingSet64
            }
        }

        $written = Write-DomovoyLedgerEntry -Entry @{
            event = 'memorytrim.apply'
            featureId = 'memory.trim'
            processes = @($targets).Count
            trimmed = $trimmed
            skipped = $skipped
            bytesBefore = $bytesBefore
            bytesAfter = $bytesAfter
            note = $honestNote
        }

        [pscustomobject]@{
            Mode = 'Apply'
            Processes = @($targets).Count
            Trimmed = $trimmed
            Skipped = $skipped
            BytesBefore = $bytesBefore
            BytesAfter = $bytesAfter
            Note = $honestNote
            LedgerTimestamp = $written['timestamp']
        }
    }
}
