function Invoke-DomovoyLedgerRewrite {
    <#
    .SYNOPSIS
    Rewrites the ledger through a migration rule and rebuilds the hash
    chain. Private helper of Invoke-DomovoyLedgerMigration (catalog 101).

    .DESCRIPTION
    The rewrite is the explicit, audited exception to append-only (invariant
    I1): it happens only through a defined migration rule, only after a
    byte-exact backup, and only when every single line of the journal is
    readable - one torn line stops the whole migration before anything is
    touched, because a migration must never lose an entry.

    The chain is rebuilt from 'genesis' over the transformed entries with
    the same hashing contract the writer uses: the hash covers the
    parsed-back canonical form of the entry (every field including the fresh
    prevHash, excluding 'hash' itself). The old chain lives on untouched
    inside the backup file.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$LedgerPath,

        [Parameter(Mandatory)]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$TargetSchema,

        [Parameter(Mandatory)]
        [scriptblock]$Transform
    )

    if (-not (Test-Path -LiteralPath $LedgerPath)) {
        throw ("Ledger rewrite stopped: the journal does not exist: {0}" -f $LedgerPath)
    }

    # Parse everything first: an unreadable line is a hard stop BEFORE any
    # byte changes. A migration that silently drops entries would be worse
    # than no migration.
    $entries = @()
    $lineNo = 0
    foreach ($line in @(Get-Content -LiteralPath $LedgerPath -ErrorAction Stop)) {
        $lineNo++
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }
        try {
            $entries += , ($line | ConvertFrom-Json)
        }
        catch {
            throw ("Ledger rewrite stopped: line {0} is not readable JSON - the journal is not rewritten when an entry could be lost." -f $lineNo)
        }
    }
    if ($entries.Count -eq 0) {
        throw 'Ledger rewrite stopped: the journal has no readable entries.'
    }

    # Byte-exact backup before the first change; the old chain survives here.
    $backupPath = Join-Path -Path (Split-Path -Parent $LedgerPath) -ChildPath (
        "ledger.backup-{0}.jsonl" -f [DateTimeOffset]::UtcNow.ToString('yyyyMMddTHHmmss')
    )
    Copy-Item -LiteralPath $LedgerPath -Destination $backupPath -ErrorAction Stop | Out-Null

    # Transform every entry and rebuild the chain from genesis.
    $newLines = @()
    $prevHash = 'genesis'
    foreach ($entry in $entries) {
        $null = & $Transform $entry

        $schemaProp = $entry.PSObject.Properties['schema']
        if ($schemaProp) {
            $schemaProp.Value = $TargetSchema
        }
        else {
            $null = $entry | Add-Member -NotePropertyName schema -NotePropertyValue $TargetSchema
        }

        $prevProp = $entry.PSObject.Properties['prevHash']
        if ($prevProp) {
            $prevProp.Value = $prevHash
        }
        else {
            $null = $entry | Add-Member -NotePropertyName prevHash -NotePropertyValue $prevHash
        }

        # Same contract as Write-DomovoyLedgerEntry: hash the PARSED-BACK
        # form of the line, so the verifier (which sees exactly that form)
        # recomputes the same digest.
        $probeLine = $entry | ConvertTo-Json -Depth 12 -Compress
        $probeEntry = $probeLine | ConvertFrom-Json
        $payload = @{}
        foreach ($prop in @($probeEntry.PSObject.Properties)) {
            if ($prop.Name -ne 'hash') { $payload[$prop.Name] = $prop.Value }
        }
        $canonical = Get-DomovoyCanonicalJson -Value $payload
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($canonical)
            $digest = $sha.ComputeHash($bytes)
            $entryHash = [System.BitConverter]::ToString($digest).Replace('-', '').ToLowerInvariant()
        }
        finally {
            $sha.Dispose()
        }

        $hashProp = $entry.PSObject.Properties['hash']
        if ($hashProp) {
            $hashProp.Value = $entryHash
        }
        else {
            $null = $entry | Add-Member -NotePropertyName hash -NotePropertyValue $entryHash
        }

        $prevHash = $entryHash
        $newLines += ($entry | ConvertTo-Json -Depth 12 -Compress)
    }

    # Write to a sibling temp file and move over the original only after the
    # full new content exists - a crash mid-write then costs nothing.
    $tempPath = "$LedgerPath.migrating"
    Set-Content -LiteralPath $tempPath -Value $newLines -Encoding UTF8 -ErrorAction Stop
    Move-Item -LiteralPath $tempPath -Destination $LedgerPath -Force -ErrorAction Stop

    return @{
        Backup   = $backupPath
        Migrated = $entries.Count
        TailHash = $prevHash
    }
}
