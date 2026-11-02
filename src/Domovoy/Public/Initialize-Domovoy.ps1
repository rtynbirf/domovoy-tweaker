function Initialize-Domovoy {
    <#
    .SYNOPSIS
    Creates the Domovoy store and the genesis ledger entry.

    .DESCRIPTION
    Idempotent: creates the store directory with snapshots/backups subfolders and,
    when the ledger file is missing, appends the genesis event to a new ledger.
    The existing ledger is never rewritten (invariant I1).

    .EXAMPLE
    Initialize-Domovoy

    .NOTES
    Store root: %ProgramData%\Domovoy, overridden by $env:DOMOVOY_STORE.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param()

    $store = Get-DomovoyStorePath
    foreach ($sub in @('snapshots', 'backups')) {
        $null = Get-DomovoyStorePath -SubPath $sub
    }

    $ledgerPath = Get-DomovoyStorePath -SubPath 'ledger.jsonl'
    $genesisCreated = $false

    if (-not (Test-Path -LiteralPath $ledgerPath)) {
        if ($PSCmdlet.ShouldProcess($ledgerPath, 'Create ledger with genesis event')) {
            $null = Write-DomovoyLedgerEntry -Entry @{
                event = 'ledger.init'
            }
            $genesisCreated = $true
        }
    }

    $module = Get-Module -Name Domovoy
    $moduleVersion = if ($module) { $module.Version.ToString() } else { 'unknown' }

    [pscustomobject]@{
        Store = $store
        Ledger = $ledgerPath
        GenesisCreated = $genesisCreated
        ModuleVersion = $moduleVersion
    }
}
