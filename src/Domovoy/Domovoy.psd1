#
# Module manifest for module 'Domovoy'
#
@{
    RootModule = 'Domovoy.psm1'
    ModuleVersion = '0.5.0'
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
        'New-DomovoyRestorePoint',
        'Get-DomovoyTelemetryReport',
        'Get-DomovoyStartupInventory',
        'Get-DomovoyDriverInventory',
        'Get-DomovoyBitLockerStatus',
        'Get-DomovoyChangeReport',
        'Invoke-DomovoyNetworkReset',
        'Undo-DomovoyNetworkReset',
        'Invoke-DomovoyEventLogCleanup',
        'Invoke-DomovoyMemoryTrim',
        'Invoke-DomovoySystemIntegrityCheck'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()

    PrivateData = @{
        PSData = @{
            Tags = @('Windows', 'Tweaker', 'Privacy', 'Telemetry', 'Debloat', 'Undo', 'Ledger', 'Drift')
            LicenseUri = 'https://github.com/rtynbirf/domovoy-tweaker/blob/main/LICENSE'
            ProjectUri = 'https://github.com/rtynbirf/domovoy-tweaker'
            ReleaseNotes = 'v0.5.0: effect verification as a full loop - a what-really-changed diff on apply (snapshot before vs probes after), 100% probe coverage with the appx.present probe, read-only reports (telemetry policies, Run/RunOnce, drivers, BitLocker, what changed since X) and dry-run actions with ledger records (network reset with a removable-settings snapshot, event log cleanup, memory trim, SFC/DISM).'
        }
    }
}
