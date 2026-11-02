function Get-DomovoyTelemetryReport {
    <#
    .SYNOPSIS
    Shows the actual values of every telemetry-related policy Domovoy knows,
    in one list. Read-only, changes nothing.

    .DESCRIPTION
    Catalog feature 15: "what is really being sent" starts with what the
    documented policy values actually are right now. The report is built from
    the feature catalog itself: every registry probe declared by privacy
    manifests is re-read from the live system and reported with its actual
    value, the expected manifest value and the feature that owns the policy.
    Nothing is modified (invariant: reports never touch the system).

    .EXAMPLE
    Get-DomovoyTelemetryReport

    .EXAMPLE
    Get-DomovoyTelemetryReport | Where-Object { -not $_.Pass }
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $rows = @()
    foreach ($feature in @(Get-DomovoyFeature)) {
        if ($feature.Category -ne 'privacy') {
            continue
        }
        try {
            $manifest = Read-FeatureManifest -Path $feature.File
        }
        catch {
            continue
        }

        foreach ($probe in @($manifest.verify)) {
            switch ($probe.type) {
                'registry.set' {
                    $actual = Get-RegistryValueSafe -Path $probe.path -Name $probe.name
                    $rows += [pscustomobject]@{
                        Feature = $manifest.id
                        Path = '{0}\{1}' -f $probe.path, $probe.name
                        Actual = [string]$actual
                        Expected = [string]$probe.value
                        Pass = ([string]$actual -eq [string]$probe.value)
                    }
                }
                'registry.absent' {
                    $actual = Get-RegistryValueSafe -Path $probe.path -Name $probe.name
                    $rows += [pscustomobject]@{
                        Feature = $manifest.id
                        Path = '{0}\{1}' -f $probe.path, $probe.name
                        Actual = [string]$actual
                        Expected = '<unset>'
                        Pass = ([string]$actual -eq '<unset>')
                    }
                }
            }
        }
    }

    return @($rows)
}
