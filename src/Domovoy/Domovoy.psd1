#
# Module manifest for module 'Domovoy'
#
@{
    RootModule = 'Domovoy.psm1'
    ModuleVersion = '1.6.0'
    GUID = '8546e1cf-4418-4133-92f4-4adcb7897011'
    # v1.6 (item 5): updatable help. The HelpInfo XML and the help cab
    # are attached to every release; "latest" serves the newest one.
    HelpInfoUri = 'https://github.com/rtynbirf/domovoy-tweaker/releases/latest/download'
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
        'Show-Domovoy',
        'Get-DomovoyGroup',
        'Invoke-DomovoyGroup',
        'Get-DomovoyLedgerSchema',
        'Invoke-DomovoyLedgerMigration',
        'Get-DomovoyShellMenuReport',
        'Get-DomovoySmartScreenStatus',
        'Get-DomovoyLanguage',
        'Set-DomovoyLanguage'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()

    PrivateData = @{
        PSData = @{
            Tags = @('Windows', 'Tweaker', 'Privacy', 'Telemetry', 'Debloat', 'Undo', 'Ledger', 'Drift', 'Network', 'Security', 'Drivers')
            LicenseUri = 'https://github.com/rtynbirf/domovoy-tweaker/blob/main/LICENSE'
            ProjectUri = 'https://github.com/rtynbirf/domovoy-tweaker'
            ReleaseNotes = 'v1.6.0: production ergonomics pass for the GUI and the portable exe - async background execution (the window never freezes, Stop button), a global error guard with a technical log instead of JIT crash dialogs, a status bar with elevation state and one-click UAC restart, catalog search, product icon and version metadata on the exe, and a detached no-console GUI launch.'
        }
    }
}