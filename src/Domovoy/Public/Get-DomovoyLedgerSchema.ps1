function Get-DomovoyLedgerSchema {
    <#
    .SYNOPSIS
    Inventories the journal schema versions and answers honestly what a
    migration would face. Read-only (catalog 101).

    .DESCRIPTION
    Walks the ledger and counts entries per schema value. Entries written by
    this module always carry schema = 1; an entry without a schema field is
    counted separately as an anomaly, and an entry with a schema NEWER than
    this module understands is reported as such - it means the journal was
    written by a newer Domovoy, and no command here will ever downgrade it.

    Read-only: the command changes nothing and writes nothing.

    .PARAMETER Path
    An explicit ledger path. Default: the ledger of the current Domovoy
    store.

    .EXAMPLE
    Get-DomovoyLedgerSchema

    .EXAMPLE
    Get-DomovoyLedgerSchema -Path C:\backup\ledger.jsonl
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string]$Path
    )

    $currentSchema = Get-DomovoyLedgerSchemaVersion
    $ledgerPath = if ($Path) { $Path } else { Get-DomovoyStorePath -SubPath 'ledger.jsonl' }

    $result = [ordered]@{
        Ledger               = $ledgerPath
        CurrentSchema        = $currentSchema
        TotalEntries         = 0
        UnreadableLines      = 0
        EntriesWithoutSchema = 0
        EntriesBelowCurrent  = 0
        EntriesAboveCurrent  = 0
        HashedEntries        = 0
        UnchainedEntries     = 0
        HighestSchema        = 0
        LowestSchema         = 0
        SchemaCounts         = [pscustomobject]@{}
        Note                 = ''
    }

    if (-not (Test-Path -LiteralPath $ledgerPath)) {
        $result.Note = 'The ledger file does not exist yet: nothing to inventory.'
        return [pscustomobject]$result
    }

    $schemaCounts = @{}
    $lines = @(Get-Content -LiteralPath $ledgerPath -ErrorAction Stop | Where-Object { $_ -and $_.Trim() })
    foreach ($line in $lines) {
        $entry = $null
        try {
            $entry = $line | ConvertFrom-Json
        }
        catch {
            $entry = $null
        }
        if (-not $entry) {
            $result.UnreadableLines++
            continue
        }
        $result.TotalEntries++

        $schemaValue = $null
        $schemaProp = $entry.PSObject.Properties['schema']
        if ($schemaProp -and $null -ne $schemaProp.Value) {
            $schemaValue = [int]$schemaProp.Value
        }

        if ($null -eq $schemaValue) {
            $result.EntriesWithoutSchema++
            $bucket = 'schema-missing'
        }
        else {
            # The bucket name carries a 'schema-' prefix on purpose: bare
            # '1' is convertible into the PSMemberTypes enum and pwsh 7.4
            # refuses Add-Member property names that look like one.
            $bucket = "schema-$schemaValue"
            if ($schemaValue -gt $result.HighestSchema) { $result.HighestSchema = $schemaValue }
            if ($schemaValue -lt $currentSchema) {
                $result.EntriesBelowCurrent++
                if ($result.LowestSchema -eq 0 -or $schemaValue -lt $result.LowestSchema) {
                    $result.LowestSchema = $schemaValue
                }
            }
            if ($schemaValue -gt $currentSchema) { $result.EntriesAboveCurrent++ }
        }
        if ($schemaCounts.ContainsKey($bucket)) { $schemaCounts[$bucket]++ }
        else { $schemaCounts[$bucket] = 1 }

        $hashProp = $entry.PSObject.Properties['hash']
        if ($hashProp -and $hashProp.Value) { $result.HashedEntries++ }
        else { $result.UnchainedEntries++ }
    }

    $countsObject = [pscustomobject]@{}
    foreach ($key in ($schemaCounts.Keys | Sort-Object)) {
        $countsObject | Add-Member -NotePropertyName $key -NotePropertyValue $schemaCounts[$key]
    }
    $result.SchemaCounts = $countsObject

    if ($result.TotalEntries -eq 0 -and $result.UnreadableLines -eq 0) {
        $result.Note = 'The ledger file exists but has no entries yet.'
    }
    elseif ($result.EntriesAboveCurrent -gt 0) {
        $result.Note = ('{0} entr(ies) use schema {1}, which is newer than this module understands ({2}): the journal was written by a newer Domovoy. Nothing here downgrades it.' -f $result.EntriesAboveCurrent, $result.HighestSchema, $currentSchema)
    }
    elseif ($result.EntriesWithoutSchema -gt 0) {
        $result.Note = ('{0} entr(ies) carry no schema field at all - inventory them before any migration.' -f $result.EntriesWithoutSchema)
    }
    else {
        $result.Note = ('Every readable entry is schema {0} or newer-but-understood; the journal matches what this module writes.' -f $currentSchema)
    }

    return [pscustomobject]$result
}
