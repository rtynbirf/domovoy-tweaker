function Test-DomovoyLedgerIntegrity {
    <#
    .SYNOPSIS
    Verifies the ledger hash chain and answers honestly what it finds.

    .DESCRIPTION
    Catalog feature 103: the append-only journal becomes tamper-evident -
    every entry written since v1.2 carries the SHA-256 of its canonical form
    and the hash of its predecessor. This command walks the whole ledger and
    recomputes both bindings.

    The answer is honest by design (invariant "honesty beats silence"):
    - a journal fully written before v1.2 has no chain at all - ChainState
      'absent', not an error;
    - a mixed journal (legacy head, v1.2 tail) verifies the hashed tail and
      counts the unchained head separately;
    - a rewritten or reordered entry breaks the chain at its exact line;
    - an unreadable (torn) line counts as broken too, with its line number.

    Read-only: the command changes nothing and writes nothing.

    .PARAMETER Path
    An explicit ledger path. Default: the ledger of the current Domovoy store.

    .PARAMETER Detail
    Also return the per-line verdicts (Line, Verdict, hashes).

    .EXAMPLE
    Test-DomovoyLedgerIntegrity

    .EXAMPLE
    Test-DomovoyLedgerIntegrity -Detail
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string]$Path,

        [switch]$Detail
    )

    $ledgerPath = if ($Path) { $Path } else { Get-DomovoyStorePath -SubPath 'ledger.jsonl' }

    $result = [ordered]@{
        Ledger             = $ledgerPath
        TotalEntries       = 0
        HashedEntries      = 0
        UnchainedEntries   = 0
        UnreadableLines    = 0
        HashMismatches     = 0
        PrevHashMismatches = 0
        ChainState         = 'absent'
        FirstBrokenLine    = 0
        Note               = ''
    }

    if (-not (Test-Path -LiteralPath $ledgerPath)) {
        $result.Note = 'The ledger file does not exist yet: nothing to verify.'
        $output = [pscustomobject]$result
        if ($Detail) {
            $output | Add-Member -NotePropertyName Detail -NotePropertyValue @()
        }
        return $output
    }

    $lines = @(Get-Content -LiteralPath $ledgerPath -ErrorAction Stop | Where-Object { $_ -and $_.Trim() })
    $expectedPrev = 'genesis'
    $detailRows = @()
    $lineNo = 0

    foreach ($line in $lines) {
        $lineNo++
        $result.TotalEntries++

        $entry = $null
        try {
            $entry = $line | ConvertFrom-Json
        }
        catch {
            $entry = $null
        }

        if (-not $entry) {
            $result.UnreadableLines++
            $result.ChainState = 'broken'
            if (-not $result.FirstBrokenLine) { $result.FirstBrokenLine = $lineNo }
            $detailRows += [pscustomobject]@{
                Line = $lineNo; Verdict = 'unreadable'
                Event = ''; FeatureId = ''
                StoredHash = ''; RecomputedHash = ''
                StoredPrevHash = ''; ExpectedPrevHash = $expectedPrev
            }
            continue
        }

        $storedHashProp = $entry.PSObject.Properties['hash']
        $storedHash = if ($storedHashProp) { [string]$storedHashProp.Value } else { '' }

        if (-not $storedHash) {
            # A legacy (pre-v1.2) entry: no chain to check, and the next
            # hashed entry must bind to 'genesis' - exactly what the writer
            # does when the tail carries no hash.
            $result.UnchainedEntries++
            $expectedPrev = 'genesis'
            $detailRows += [pscustomobject]@{
                Line = $lineNo; Verdict = 'unchained'
                Event = [string]$entry.event; FeatureId = [string]$entry.featureId
                StoredHash = ''; RecomputedHash = ''
                StoredPrevHash = ''; ExpectedPrevHash = ''
            }
            continue
        }

        $result.HashedEntries++

        # Rebuild the hashed payload: the parsed entry minus the hash field.
        $payload = @{}
        foreach ($prop in @($entry.PSObject.Properties)) {
            if ($prop.Name -ne 'hash') { $payload[$prop.Name] = $prop.Value }
        }
        $canonical = Get-DomovoyCanonicalJson -Value $payload
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($canonical)
            $digest = $sha.ComputeHash($bytes)
            $recomputed = [System.BitConverter]::ToString($digest).Replace('-', '').ToLowerInvariant()
        }
        finally {
            $sha.Dispose()
        }

        $storedPrevProp = $entry.PSObject.Properties['prevHash']
        $storedPrev = if ($storedPrevProp) { [string]$storedPrevProp.Value } else { '' }

        $verdict = 'ok'
        if ($recomputed -ne $storedHash) {
            $result.HashMismatches++
            $verdict = 'hash-mismatch'
        }
        if ($storedPrev -ne $expectedPrev) {
            $result.PrevHashMismatches++
            $verdict = 'prev-hash-mismatch'
        }
        if ($verdict -ne 'ok') {
            $result.ChainState = 'broken'
            if (-not $result.FirstBrokenLine) { $result.FirstBrokenLine = $lineNo }
        }

        $detailRows += [pscustomobject]@{
            Line = $lineNo; Verdict = $verdict
            Event = [string]$entry.event; FeatureId = [string]$entry.featureId
            StoredHash = $storedHash; RecomputedHash = $recomputed
            StoredPrevHash = $storedPrev; ExpectedPrevHash = $expectedPrev
        }

        # The next entry binds to this one's stored hash.
        $expectedPrev = $storedHash
    }

    if ($result.HashedEntries -eq 0) {
        $result.ChainState = 'absent'
        $result.Note = ('No hashed entries: all {0} entries predate v1.2, so there is no chain to verify. This is an honest answer, not a failure.' -f $result.TotalEntries)
    }
    elseif ($result.ChainState -eq 'broken') {
        $result.Note = ('The chain is broken: {0} hash mismatch(es), {1} predecessor mismatch(es), first problem at line {2}. The journal was edited or reordered after the fact.' -f $result.HashMismatches, $result.PrevHashMismatches, $result.FirstBrokenLine)
    }
    else {
        $result.ChainState = 'ok'
        $result.Note = ('Hash chain verified: {0} of {1} entries bound (the rest predate v1.2 and are counted as unchained).' -f $result.HashedEntries, $result.TotalEntries)
    }

    $output = [pscustomobject]$result
    if ($Detail) {
        $output | Add-Member -NotePropertyName Detail -NotePropertyValue $detailRows
    }
    return $output
}
