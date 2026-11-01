function Invoke-DomovoyFeature {
    <#
    .SYNOPSIS
    Shows the plan (dry-run by default) or applies a Domovoy feature.

    .DESCRIPTION
    Dry-run is the default: without -Apply the command returns the plan with the
    current state and changes nothing. With -Apply it requires elevation, creates
    a system restore point (soft), captures a snapshot of the current state,
    executes the manifest operations, runs verification probes and appends a
    feature.apply event to the ledger.

    .EXAMPLE
    Invoke-DomovoyFeature -Id services.diagtrack.disabled

    .EXAMPLE
    Invoke-DomovoyFeature -Id services.diagtrack.disabled -Apply
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ById')]
        [string]$Id,

        [Parameter(Mandatory, ParameterSetName = 'ByFile')]
        [string]$ManifestFile,

        [switch]$Apply,

        [switch]$SkipRestorePoint
    )

    if ($PSCmdlet.ParameterSetName -eq 'ByFile') {
        $manifest = Read-FeatureManifest -Path $ManifestFile
    }
    else {
        $feature = Get-DomovoyFeature -Id $Id
        if (-not $feature) {
            throw "Feature not found: $Id"
        }
        $manifest = Read-FeatureManifest -Path $feature[0].File
    }

    # Build the plan: for every operation, capture the current state.
    $plan = @()
    foreach ($op in @($manifest.ops)) {
        switch ($op.type) {
            'registry.set' {
                $currentType = 'None'
                if (Test-Path -LiteralPath $op.path) {
                    try {
                        $currentType = [string](Get-Item -LiteralPath $op.path -ErrorAction Stop).GetValueKind($op.name)
                    }
                    catch {
                        $currentType = 'None'
                    }
                }
                $plan += [pscustomobject]@{
                    Op = 'registry.set'
                    Target = '{0}\{1}' -f $op.path, $op.name
                    Current = (Get-RegistryValueSafe -Path $op.path -Name $op.name)
                    CurrentType = $currentType
                    New = [string]$op.value
                    NewType = $op.valueType
                }
            }
            'service.startup' {
                $service = Get-Service -Name $op.name -ErrorAction SilentlyContinue
                $plan += [pscustomobject]@{
                    Op = 'service.startup'
                    Target = $op.name
                    Current = if ($service) { [string]$service.StartType } else { '<missing>' }
                    CurrentType = $null
                    New = $op.startupType
                    NewType = $null
                }
            }
            default {
                throw "Unsupported op type: $($op.type)"
            }
        }
    }

    # Dry-run by default (invariant I3).
    if (-not $Apply) {
        [pscustomobject]@{
            Feature = $manifest.id
            Mode = 'DryRun'
            Plan = $plan
        }
        return
    }

    # Elevation is checked explicitly (invariant I5).
    if (-not (Test-DomovoyAdmin)) {
        throw 'Applying features requires an elevated PowerShell session.'
    }

    if ($PSCmdlet.ShouldProcess($manifest.id, 'Apply feature operations')) {
        # System restore point (soft: Windows allows one per 24h).
        if (-not $SkipRestorePoint) {
            try {
                New-DomovoyRestorePoint -Description "Domovoy: $($manifest.id)" -ErrorAction Stop | Out-Null
            }
            catch {
                Write-Verbose ("Restore point was not created: {0}" -f $_.Exception.Message)
            }
        }

        # Snapshot before the first operation (invariant I2).
        $snapshot = @()
        foreach ($op in @($manifest.ops)) {
            switch ($op.type) {
                'registry.set' {
                    $kind = 'None'
                    if (Test-Path -LiteralPath $op.path) {
                        try {
                            $kind = [string](Get-Item -LiteralPath $op.path -ErrorAction Stop).GetValueKind($op.name)
                        }
                        catch {
                            $kind = 'None'
                        }
                    }
                    $snapshot += @{
                        op = 'registry.set'
                        path = $op.path
                        name = $op.name
                        previousValue = (Get-RegistryValueSafe -Path $op.path -Name $op.name)
                        previousType = $kind
                    }
                }
                'service.startup' {
                    $service = Get-Service -Name $op.name -ErrorAction SilentlyContinue
                    $snapshot += @{
                        op = 'service.startup'
                        name = $op.name
                        previousValue = if ($service) { [string]$service.StartType } else { '<missing>' }
                    }
                }
            }
        }

        # Execute operations.
        foreach ($op in @($manifest.ops)) {
            switch ($op.type) {
                'registry.set' {
                    if (-not (Test-Path -LiteralPath $op.path)) {
                        $null = New-Item -Path $op.path -ItemType Directory -Force
                    }
                    $null = New-ItemProperty -LiteralPath $op.path -Name $op.name -Value $op.value -PropertyType $op.valueType -Force
                }
                'service.startup' {
                    Set-Service -Name $op.name -StartupType $op.startupType
                }
            }
        }

        # Verify and record.
        $verification = Test-DomovoyEffect -Manifest $manifest
        $written = Write-DomovoyLedgerEntry -Entry @{
            event = 'feature.apply'
            featureId = $manifest.id
            featureVersion = $manifest.version
            snapshot = $snapshot
            verification = $verification
        }

        [pscustomobject]@{
            Feature = $manifest.id
            Mode = 'Apply'
            Verification = $verification
            LedgerTimestamp = $written['timestamp']
        }
    }
}
