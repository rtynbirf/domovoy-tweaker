function Invoke-DomovoyLedgerMigration {
    <#
    .SYNOPSIS
    Migrates the journal to the current schema version - explicitly, with a
    plan by default and an honest verdict when there is nothing to do
    (catalog 101).

    .DESCRIPTION
    The mechanism for schema migration: inventory, rule lookup, backup,
    rewrite with a rebuilt hash chain and a 'ledger.migrate' audit entry.
    Today it exists so that the day schema 2 is defined, the transformation
    ships into a tested machine instead of a risky one-off script.

    The verdicts are honest by design:
    - 'empty'            - no journal yet;
    - 'already-current'  - every entry already carries the current schema;
    - 'future-entries'   - the journal was written by a NEWER Domovoy:
      refused loudly, a downgrade is never attempted;
    - 'migration-not-defined' - older entries exist, but no transformation
      rule for them is registered in this release. Nothing is changed: the
      rule will ship together with the release that defines the new schema.
    - 'migration-defined' - a rule exists and -Apply would rewrite the
      journal (backup first, chain rebuilt, audit entry appended).

    Without -Apply nothing is changed (invariant I3). The rewrite itself is
    the explicit, audited exception to append-only: it happens only through
    a defined rule, only after a byte-exact backup, and only when every
    line of the journal is readable.

    .PARAMETER TargetSchema
    Migrate to this journal schema version. Defaults to the version this
    module writes.

    .PARAMETER Apply
    Perform the migration when a rule is defined. Without it - the plan.

    .EXAMPLE
    Invoke-DomovoyLedgerMigration

    .EXAMPLE
    Invoke-DomovoyLedgerMigration -Apply
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [ValidateRange(1, [int]::MaxValue)]
        [int]$TargetSchema = 0,

        [switch]$Apply
    )

    $currentSchema = Get-DomovoyLedgerSchemaVersion
    if ($TargetSchema -le 0) {
        $TargetSchema = $currentSchema
    }

    $ledgerPath = Get-DomovoyStorePath -SubPath 'ledger.jsonl'
    $inventory = Get-DomovoyLedgerSchema -Path $ledgerPath

    $verdict = 'already-current'
    $note = ''
    $rule = $null

    if ($inventory.TotalEntries -eq 0 -and $inventory.UnreadableLines -eq 0 -and -not (Test-Path -LiteralPath $ledgerPath)) {
        $verdict = 'empty'
        $note = 'The journal does not exist yet: nothing to migrate.'
    }
    elseif ($inventory.EntriesAboveCurrent -gt 0 -and $TargetSchema -lt $inventory.HighestSchema) {
        $verdict = 'future-entries'
        $note = ('The journal contains schema {0} entries written by a newer Domovoy. A downgrade is never attempted - open the journal with the Domovoy version that wrote it.' -f $inventory.HighestSchema)
    }
    elseif ($inventory.EntriesBelowCurrent -gt 0) {
        $rule = Get-DomovoyLedgerMigrationRule -From $inventory.LowestSchema -To $TargetSchema
        if ($rule) {
            $verdict = 'migration-defined'
            $note = ('{0} entr(ies) below schema {1}: -Apply would back up the journal, rewrite {2} entries and rebuild the hash chain.' -f $inventory.EntriesBelowCurrent, $currentSchema, $inventory.EntriesBelowCurrent)
        }
        else {
            $verdict = 'migration-not-defined'
            $note = ('{0} entr(ies) below schema {1}, but this release defines no transformation for them. Nothing was changed: the rule ships together with the release that defines the new schema. The journal stays fully readable (MAJOR policy).' -f $inventory.EntriesBelowCurrent, $currentSchema)
        }
    }
    elseif ($inventory.TotalEntries -eq 0) {
        $verdict = 'empty'
        $note = 'The journal has no readable entries: nothing to migrate.'
    }
    else {
        $verdict = 'already-current'
        $note = ('Every readable entry already carries schema {0}: nothing to migrate.' -f $currentSchema)
    }

    $wouldRewrite = $Apply -and $verdict -eq 'migration-defined'

    # An explicit -Apply against a newer journal is a loud refusal, not a
    # silent no-op: the caller must never walk away thinking the journal was
    # handled. Without -Apply the same fact is a plan verdict.
    if ($Apply -and $verdict -eq 'future-entries') {
        throw $note
    }

    if ($wouldRewrite -and -not $PSCmdlet.ShouldProcess($ledgerPath, 'Migrate ledger schema')) {
        $Apply = $false
        $wouldRewrite = $false
    }

    $backup = $null
    if ($wouldRewrite) {
        $rewrite = Invoke-DomovoyLedgerRewrite -LedgerPath $ledgerPath -TargetSchema $TargetSchema -Transform $rule.Transform
        $backup = $rewrite.Backup

        # The audit entry chains onto the freshly rebuilt tail.
        $null = Write-DomovoyLedgerEntry -Entry @{
            event         = 'ledger.migrate'
            fromSchema    = [int]$rule.From
            toSchema      = $TargetSchema
            migratedCount = $rewrite.Migrated
            backupFile    = (Split-Path -Leaf $rewrite.Backup)
            chainState    = (Test-DomovoyLedgerIntegrity).ChainState
        }
        $note = ('Migration applied: {0} entr(ies) rewritten to schema {1}, hash chain rebuilt, backup: {2}.' -f $rewrite.Migrated, $TargetSchema, $rewrite.Backup)
    }

    [pscustomobject]@{
        Ledger         = $ledgerPath
        Mode           = if ($Apply) { 'Apply' } else { 'DryRun' }
        CurrentSchema  = $currentSchema
        TargetSchema   = $TargetSchema
        Verdict        = $verdict
        Applied        = [bool]$wouldRewrite
        Backup         = $backup
        TotalEntries   = $inventory.TotalEntries
        EntriesBelow   = $inventory.EntriesBelowCurrent
        EntriesAbove   = $inventory.EntriesAboveCurrent
        SchemaCounts   = $inventory.SchemaCounts
        Note           = $note
    }
}
