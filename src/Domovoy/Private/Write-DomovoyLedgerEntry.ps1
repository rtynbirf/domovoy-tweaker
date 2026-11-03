function Write-DomovoyLedgerEntry {
    <#
    .SYNOPSIS
    Appends one event to the Domovoy ledger (append-only JSONL, invariant I1).

    .DESCRIPTION
    Since v1.2 every new entry is bound to its predecessor by a hash chain
    (catalog 103): prevHash carries the hash of the previous entry (or the
    literal 'genesis' when the journal tail has no hashed entry yet), and
    hash carries the SHA-256 over the canonical JSON form of the entry itself
    - every field including prevHash, excluding the hash field. The change is
    additive: schema stays 1, journals written before v1.2 load and verify as
    'unchained' - the SemVer MAJOR policy holds.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Entry
    )

    $ledgerPath = Get-DomovoyStorePath -SubPath 'ledger.jsonl'

    $Entry['schema'] = Get-DomovoyLedgerSchemaVersion
    $Entry['tool'] = 'Domovoy'
    $module = Get-Module -Name Domovoy
    if ($module) {
        $Entry['toolVersion'] = $module.Version.ToString()
    }
    else {
        $Entry['toolVersion'] = 'unknown'
    }
    $Entry['timestamp'] = [DateTimeOffset]::UtcNow.ToString('o')

    # Hash chain (catalog 103): read only the tail - the ledger can be long
    # and every entry is bound to exactly one predecessor. A torn last line
    # (a crash mid-write) must not block the next honest append; the gap is
    # reported by Test-DomovoyLedgerIntegrity instead.
    $previousHash = 'genesis'
    if (Test-Path -LiteralPath $ledgerPath) {
        $lastLine = Get-Content -LiteralPath $ledgerPath -Tail 1 -ErrorAction SilentlyContinue
        if ($lastLine) {
            try {
                $lastEntry = $lastLine | ConvertFrom-Json
                $lastHashProp = $lastEntry.PSObject.Properties['hash']
                if ($lastHashProp -and $lastHashProp.Value) {
                    $previousHash = [string]$lastHashProp.Value
                }
            }
            catch {
                $previousHash = 'genesis'
            }
        }
    }
    $Entry['prevHash'] = $previousHash

    # The hash covers everything the entry will store except 'hash' itself.
    # It is computed over the PARSED-BACK form of the line, not over the
    # in-memory hashtable: ConvertFrom-Json on the verify side coerces values
    # (an ISO timestamp string becomes a DateTime object, JSON numbers become
    # Int64), and the verifier sees exactly those coerced values. Hashing the
    # same coerced form on both sides is what makes the chain verifiable.
    $probeLine = $Entry | ConvertTo-Json -Depth 12 -Compress
    $probeEntry = $probeLine | ConvertFrom-Json
    $canonicalInput = @{}
    foreach ($prop in @($probeEntry.PSObject.Properties)) {
        if ($prop.Name -ne 'hash') { $canonicalInput[$prop.Name] = $prop.Value }
    }
    $canonical = Get-DomovoyCanonicalJson -Value $canonicalInput
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($canonical)
        $digest = $sha.ComputeHash($bytes)
        $Entry['hash'] = [System.BitConverter]::ToString($digest).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }

    $line = $Entry | ConvertTo-Json -Depth 12 -Compress

    # Invariant I1: an append must never fail merely because the store
    # directory does not exist yet. The parent is ensured through .NET
    # directly - that path cannot be shadowed by test mocks of the
    # Test-Path/New-Item cmdlets and behaves identically on every volume.
    $ledgerDir = [System.IO.Path]::GetDirectoryName($ledgerPath)
    if (-not [string]::IsNullOrEmpty($ledgerDir) -and -not [System.IO.Directory]::Exists($ledgerDir)) {
        $null = [System.IO.Directory]::CreateDirectory($ledgerDir)
    }
    Add-Content -LiteralPath $ledgerPath -Value $line -Encoding UTF8

    return $Entry
}
