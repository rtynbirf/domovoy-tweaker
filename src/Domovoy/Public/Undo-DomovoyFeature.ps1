function Undo-DomovoyFeature {
    <#
    .SYNOPSIS
    Undoes a feature by restoring the exact state captured before its last apply.

    .DESCRIPTION
    Finds the most recent feature.apply event for the feature in the ledger and
    restores every captured value (registry values with their original types,
    service startup types, stopped services started again when they were
    running). Values that did not exist before the tweak are removed.
    Without -Apply the command is a dry-run: it shows what would be restored.

    .EXAMPLE
    Undo-DomovoyFeature -Id services.diagtrack.disabled

    .EXAMPLE
    Undo-DomovoyFeature -Id services.diagtrack.disabled -Apply
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$Id,

        [switch]$Apply
    )

    if (-not (Test-Path (Get-DomovoyStorePath -SubPath 'ledger.jsonl'))) {
        throw 'Ledger not found. Nothing to undo.'
    }

    $entry = Get-DomovoyLedger -FeatureId $Id -Event 'feature.apply' -Last 1000000 |
        Select-Object -Last 1

    if (-not $entry) {
        throw "No ledger entry to undo for: $Id"
    }

    # Dry-run by default (invariant I3).
    if (-not $Apply) {
        [pscustomobject]@{
            Feature = $Id
            Mode = 'DryRun'
            AppliedAt = $entry.timestamp
            Snapshot = $entry.snapshot
        }
        return
    }

    # Elevation is checked explicitly (invariant I5).
    if (-not (Test-DomovoyAdmin)) {
        throw 'Undo requires an elevated PowerShell session.'
    }

    if ($PSCmdlet.ShouldProcess($Id, 'Restore snapshot')) {
        foreach ($state in @($entry.snapshot)) {
            switch ($state.op) {
                'registry.set' {
                    if ($state.previousValue -eq '<unset>') {
                        Remove-ItemProperty -LiteralPath $state.path -Name $state.name -ErrorAction SilentlyContinue
                    }
                    elseif ($state.previousType -and $state.previousType -ne 'None') {
                        $null = New-ItemProperty -LiteralPath $state.path -Name $state.name -Value $state.previousValue -PropertyType $state.previousType -Force
                    }
                    else {
                        $null = New-ItemProperty -LiteralPath $state.path -Name $state.name -Value $state.previousValue -Force
                    }
                }
                'registry.delete' {
                    # A deleted value is recreated with its exact type and data;
                    # if the value did not exist before apply, the absence is restored.
                    if ($state.previousType -and $state.previousType -ne 'None') {
                        if (-not (Test-Path -LiteralPath $state.path)) {
                            $null = New-Item -Path $state.path -ItemType Directory -Force
                        }
                        $null = New-ItemProperty -LiteralPath $state.path -Name $state.name -Value $state.previousValue -PropertyType $state.previousType -Force
                    }
                    elseif ($state.previousValue -eq '<unset>') {
                        Remove-ItemProperty -LiteralPath $state.path -Name $state.name -ErrorAction SilentlyContinue
                    }
                }
                'service.startup' {
                    if ($state.previousValue -ne '<missing>') {
                        Set-Service -Name $state.name -StartupType $state.previousValue
                    }
                }
                'service.stop' {
                    if ($state.previousStatus -eq 'Running') {
                        Start-Service -Name $state.name -ErrorAction SilentlyContinue
                    }
                    elseif ($state.previousStatus -eq 'Stopped') {
                        $current = Get-Service -Name $state.name -ErrorAction SilentlyContinue
                        if ($current -and $current.Status -eq 'Running') {
                            Stop-Service -Name $state.name -Force -ErrorAction SilentlyContinue
                        }
                    }
                }
            }
        }

        $verification = $null
        try {
            $manifest = Get-DomovoyManifestForFeature -Id $Id -LedgerEntry $entry
            $verification = Test-DomovoyEffect -Manifest $manifest
        }
        catch {
            Write-Verbose ("Post-undo verification was not possible: {0}" -f $_.Exception.Message)
        }
        $written = Write-DomovoyLedgerEntry -Entry @{
            event = 'feature.undo'
            featureId = $Id
            verification = $verification
        }

        [pscustomobject]@{
            Feature = $Id
            Mode = 'Undo'
            Verification = $verification
            LedgerTimestamp = $written['timestamp']
        }
    }
}
