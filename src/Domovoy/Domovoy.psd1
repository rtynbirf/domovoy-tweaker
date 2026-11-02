#
# Module manifest for module 'Domovoy'
#
@{
    RootModule = 'Domovoy.psm1'
    ModuleVersion = '1.2.0'
    GUID = '8546e1cf-4418-4133-92f4-4adcb7897011'
    Author = 'rtynbirf'
    CompanyName = 'Domovoy contributors'
    Copyright = '(c) 2026 rtynbirf. MIT licensed.'
    Description = 'Domovoy - Windows tweaker as a state, not an event: change ledger, per-feature undo, drift sentinel with opt-in auto-heal, effect verification. Prototype.'

    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')

    FunctionsToExport = @(
        'Initialize-Domovoy',
        'Get-DomovoyFeature',
        'Invoke-DomovoyFeature',
        'Undo-DomovoyFeature',
        'Get-DomovoyLedger',
        'Invoke-DomovoyDriftScan',
        'Invoke-DomovoyAutoHeal',
        'Register-DomovoyWatchdog',
        'Unregister-DomovoyWatchdog',
        'Test-DomovoyEffect',
        'Backup-DomovoySnapshot',
        'Backup-DomovoyServiceState',
        'Backup-DomovoyTaskState',
        'Get-DomovoyProfile',
        'Invoke-DomovoyProfile',
        'Invoke-DomovoyCleanup',
        'New-DomovoyRestorePoint',
        'Get-DomovoyTelemetryReport',
        'Get-DomovoyStartupInventory',
        'Get-DomovoyDriverInventory',
        'Get-DomovoyLsaStatus',
        'Get-DomovoyBitLockerStatus',
        'Get-DomovoyChangeReport',
        'Invoke-DomovoyNetworkReset',
        'Undo-DomovoyNetworkReset',
        'Invoke-DomovoyEventLogCleanup',
        'Invoke-DomovoyMemoryTrim',
        'Invoke-DomovoySystemIntegrityCheck',
        'Get-DomovoyPrivilege',
        'Enable-DomovoyPrivilege',
        'Disable-DomovoyPrivilege',
        'Set-DomovoyFileOwner',
        'Undo-DomovoyFileOwner',
        'Invoke-DomovoyFileAttributeClear',
        'Undo-DomovoyFileAttributeClear',
        'Backup-DomovoyBitLockerKey',
        'Invoke-DomovoyDriverDedup',
        'Switch-DomovoyTheme',
        'Get-DomovoyNetworkReport',
        'Export-DomovoyNetworkState',
        'Restore-DomovoyNetworkState',
        'Export-DomovoyPolicy',
        'Test-DomovoyLedgerIntegrity',
        'Get-DomovoyDriverRollbackReport',
        'Invoke-DomovoyComponentStoreCleanup',
        'Show-Domovoy'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()

    PrivateData = @{
        PSData = @{
            Tags = @('Windows', 'Tweaker', 'Privacy', 'Telemetry', 'Debloat', 'Undo', 'Ledger', 'Drift', 'Network', 'Security', 'Drivers')
            LicenseUri = 'https://github.com/rtynbirf/domovoy-tweaker/blob/main/LICENSE'
            ProjectUri = 'https://github.com/rtynbirf/domovoy-tweaker'
            ReleaseNotes = 'v1.2.0: the ledger becomes tamper-evident (a SHA-256 hash chain with an honest verifier, catalog 103), a new file.timestamp op with all four projections and probes, five documented catalog policies (taskbar alignment, VisualFX profiles, automatic DoH off, Office client telemetry off), the driver rollback-readiness report and the component store cleanup that only triggers the built-in Windows servicing task.'
        }
    }
}
