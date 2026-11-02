function Invoke-DomovoySystemIntegrityCheck {
    <#
    .SYNOPSIS
    Shows the integrity check plan (dry-run by default) or runs SFC or DISM
    and records the result in the ledger.

    .DESCRIPTION
    Catalog feature 51: system file integrity is checked with the built-in
    tools (sfc /scannow or DISM /Online /Cleanup-Image /ScanHealth), but not
    quietly: the run, its exit code and the full output go to the Domovoy
    store (integrity-<tool>-<timestamp>.txt) and the fact goes to the ledger
    as an integritycheck.apply event. The check itself changes nothing; it is
    a scan, and the report is the point.

    Applying requires elevation (invariant I5). The scan can take several
    minutes; its output can be large, so only the exit code goes into the
    ledger entry and the full output stays in the store file.

    .PARAMETER Tool
    Sfc (sfc /scannow, default) or Dism (DISM /Online /Cleanup-Image /ScanHealth).

    .PARAMETER Apply
    Run the check. Without this switch only the plan is shown.

    .EXAMPLE
    Invoke-DomovoySystemIntegrityCheck

    .EXAMPLE
    Invoke-DomovoySystemIntegrityCheck -Tool Dism -Apply
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [ValidateSet('Sfc', 'Dism')]
        [string]$Tool = 'Sfc',

        [switch]$Apply
    )

    $command = switch ($Tool) {
        'Sfc' { @{ Exe = 'sfc.exe'; Arguments = @('/scannow') } }
        'Dism' { @{ Exe = 'Dism.exe'; Arguments = @('/Online', '/Cleanup-Image', '/ScanHealth') } }
    }

    if (-not $Apply) {
        [pscustomobject]@{
            Tool = $Tool
            Mode = 'DryRun'
            Command = ('{0} {1}' -f $command.Exe, ($command.Arguments -join ' '))
            Note = 'The scan changes nothing; the result is recorded in the ledger.'
        }
        return
    }

    if (-not (Test-DomovoyAdmin)) {
        throw 'Running the integrity check requires an elevated PowerShell session.'
    }

    if ($PSCmdlet.ShouldProcess($Tool, 'Run system file integrity scan')) {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $outputFile = Get-DomovoyStorePath -SubPath ('integrity-{0}-{1}.txt' -f $Tool.ToLowerInvariant(), $stamp)

        $stdoutPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("domovoy-integrity-" + [guid]::NewGuid().ToString('N') + ".out")

        $proc = Start-Process -FilePath $command.Exe -ArgumentList $command.Arguments `
            -Wait -PassThru -NoNewWindow `
            -RedirectStandardOutput $stdoutPath `
            -RedirectStandardError ($stdoutPath + '.err')

        $output = ''
        if (Test-Path -LiteralPath $stdoutPath) {
            $output = Get-Content -LiteralPath $stdoutPath -Raw -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath ($stdoutPath + '.err')) {
            $errText = Get-Content -LiteralPath ($stdoutPath + '.err') -Raw -ErrorAction SilentlyContinue
            if ($errText) {
                $output = $output + "`n" + $errText
            }
        }
        $output | Set-Content -LiteralPath $outputFile -Encoding UTF8
        Remove-Item -LiteralPath $stdoutPath, ($stdoutPath + '.err') -Force -ErrorAction SilentlyContinue

        $written = Write-DomovoyLedgerEntry -Entry @{
            event = 'integritycheck.apply'
            featureId = 'integrity.' + $Tool.ToLowerInvariant()
            tool = $Tool
            command = ('{0} {1}' -f $command.Exe, ($command.Arguments -join ' '))
            exitCode = $proc.ExitCode
            outputFile = $outputFile
        }

        [pscustomobject]@{
            Tool = $Tool
            ExitCode = $proc.ExitCode
            OutputFile = $outputFile
            LedgerTimestamp = $written['timestamp']
        }
    }
}
