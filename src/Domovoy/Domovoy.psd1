#
# Module manifest for module 'Domovoy'
#
@{
    RootModule = 'Domovoy.psm1'
    ModuleVersion = '0.4.0'
    GUID = '8546e1cf-4418-4133-92f4-4adcb7897011'
    Author = 'rtynbirf'
    CompanyName = 'Domovoy contributors'
    Copyright = '(c) 2026 rtynbirf. MIT licensed.'
    Description = 'Domovoy - Windows tweaker as a state, not an event: change ledger, per-feature undo, drift sentinel, effect verification. Prototype.'

    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')

    FunctionsToExport = @(
        'Initialize-Domovoy',
        'Get-DomovoyFeature',
        'Invoke-DomovoyFeature',
        'Undo-DomovoyFeature',
        'Get-DomovoyLedger',
        'Invoke-DomovoyDriftScan',
        'Test-DomovoyEffect',
        'Backup-DomovoySnapshot',
        'Backup-DomovoyServiceState',
        'Get-DomovoyProfile',
        'Invoke-DomovoyProfile',
        'Invoke-DomovoyCleanup',
        'New-DomovoyRestorePoint'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()

    PrivateData = @{
        PSData = @{
            Tags = @('Windows', 'Tweaker', 'Privacy', 'Telemetry', 'Debloat', 'Undo', 'Ledger', 'Drift')
            LicenseUri = 'https://github.com/rtynbirf/domovoy-tweaker/blob/main/LICENSE'
            ProjectUri = 'https://github.com/rtynbirf/domovoy-tweaker'
            ReleaseNotes = 'v0.4.0: drift sentinel with a baseline from the last verified snapshot (dates, -Since, undone features skipped), scheduler.task op with full projections, temp cleanup with an honest volume report, five documented features (26 total).'
        }
    }
}
