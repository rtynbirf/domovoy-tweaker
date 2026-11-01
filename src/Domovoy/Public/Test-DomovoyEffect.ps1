function Test-DomovoyEffect {
    <#
    .SYNOPSIS
    Runs verification probes for a feature and returns an honest pass/fail matrix.

    .DESCRIPTION
    Every probe asks the system one minimal question (registry value, service
    startup type) and compares the actual state with the expected one. A FAIL is
    a normal, honest answer - not an error.

    .EXAMPLE
    Test-DomovoyEffect -Id policy.telemetry.level0
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ById')]
        [string]$Id,

        [Parameter(Mandatory, ParameterSetName = 'ByManifest')]
        [psobject]$Manifest
    )

    if ($PSCmdlet.ParameterSetName -eq 'ById') {
        $feature = Get-DomovoyFeature -Id $Id
        if (-not $feature) {
            throw "Feature not found: $Id"
        }
        $Manifest = Read-FeatureManifest -Path $feature[0].File
    }

    $results = @()
    foreach ($probe in @($Manifest.verify)) {
        $target = $null
        $expected = $null
        $actual = $null

        switch ($probe.type) {
            'registry.set' {
                $target = '{0}\{1}' -f $probe.path, $probe.name
                $expected = [string]$probe.value
                $actual = Get-RegistryValueSafe -Path $probe.path -Name $probe.name
            }
            'service.startup' {
                $target = $probe.name
                $expected = [string]$probe.startupType
                $service = Get-Service -Name $probe.name -ErrorAction SilentlyContinue
                if ($service) {
                    $actual = [string]$service.StartType
                }
                else {
                    $actual = '<missing>'
                }
            }
            default {
                $target = '<unknown-probe>'
                $expected = '?'
                $actual = '<unknown-probe>'
            }
        }

        $results += [pscustomobject]@{
            Probe = $probe.type
            Target = $target
            Expected = $expected
            Actual = $actual
            Pass = ($actual -eq $expected)
        }
    }

    $failed = @($results | Where-Object { -not $_.Pass })

    [pscustomobject]@{
        Feature = $Manifest.id
        AllPass = ($failed.Count -eq 0)
        Results = $results
    }
}
