#
# Module manifest for module 'Domovoy'
#
@{
    RootModule = 'Domovoy.psm1'
    ModuleVersion = '1.1.0'
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
            ReleaseNotes = 'v0.6.0: drift auto-heal as an opt-in contour (Invoke-DomovoyAutoHeal with a journaled cycle and a scheduled watchdog task the user registers explicitly), DNS profiles as manifests (network.dns op with probe, snapshot and undo), driver dedup only after a full .cab backup, file attribute clearing and owner change with ledger snapshots, journaled token privilege management and an explicit BitLocker recovery key backup.'
        }
    }
}
