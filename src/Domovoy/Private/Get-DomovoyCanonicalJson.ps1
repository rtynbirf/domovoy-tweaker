function Get-DomovoyCanonicalJson {
    <#
    .SYNOPSIS
    Serializes any ledger value into a canonical JSON string: object keys are
    sorted (ordinal, recursively), strings are escaped minimally, numbers use
    the invariant culture.

    .DESCRIPTION
    The ledger hash chain (catalog 103) needs one and the same input to always
    produce one and the same string - on Windows PowerShell 5.1 and on
    PowerShell 7.x alike. ConvertTo-Json cannot promise that (hashtable key
    order and non-ASCII escaping differ between editions), so the chain hashes
    this own serializer instead. It is deliberately small and readable: the
    hash is only as trustworthy as the code that feeds it.

    Both sides of the chain use it the same way:
    - the writer canonicalizes the in-memory entry before hashing;
    - the verifier canonicalizes the parsed ledger line (minus 'hash') before
      re-hashing. Parsing normalizes the value tree, so both sides see the
      same input regardless of how ConvertTo-Json formatted the stored line.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $Value,

        [int]$Depth = 0
    )

    if ($Depth -gt 64) {
        throw 'Get-DomovoyCanonicalJson: nesting deeper than 64 levels (a reference loop?).'
    }

    # Unwrap plain PSObject wrappers (int, WMI adapters, ...) so the type
    # checks below see the real value. PSCustomObject's BaseObject is the
    # instance itself, so the reference check keeps it untouched.
    if ($Value -is [PSObject]) {
        $base = $Value.PSObject.BaseObject
        if ($null -ne $base -and -not [object]::ReferenceEquals($base, $Value)) {
            $Value = $base
        }
    }

    if ($null -eq $Value) {
        return 'null'
    }

    if ($Value -is [bool]) {
        if ($Value) { return 'true' }
        return 'false'
    }

    if ($Value -is [string]) {
        return (ConvertTo-DomovoyCanonicalString -Text $Value)
    }

    if ($Value -is [char]) {
        return (ConvertTo-DomovoyCanonicalString -Text ([string]$Value))
    }

    if ($Value -is [DateTime] -or $Value -is [DateTimeOffset]) {
        # Ledger timestamps are always stored as strings; if a caller still
        # passes a date, pin it to one deterministic spelling.
        return (ConvertTo-DomovoyCanonicalString -Text ([DateTimeOffset]$Value).UtcDateTime.ToString('o', [System.Globalization.CultureInfo]::InvariantCulture))
    }

    if ($Value -is [sbyte] -or $Value -is [byte] -or $Value -is [int16] -or $Value -is [uint16] -or
        $Value -is [int] -or $Value -is [uint32] -or $Value -is [long] -or $Value -is [uint64]) {
        return $Value.ToString([System.Globalization.CultureInfo]::InvariantCulture)
    }

    if ($Value -is [double] -or $Value -is [single] -or $Value -is [decimal]) {
        # 'R' is the shortest round-trip form for floats; decimals render
        # exactly. Invariant culture pins the decimal separator to '.'.
        return $Value.ToString('R', [System.Globalization.CultureInfo]::InvariantCulture)
    }

    if ($Value -is [System.Collections.IDictionary]) {
        $parts = @()
        # Ordinal sort: culture-independent, so a ledger written on any
        # machine verifies on any machine.
        $keyList = [System.Collections.Generic.List[string]]::new()
        foreach ($k in @($Value.Keys)) { $keyList.Add([string]$k) }
        $keyList.Sort([System.StringComparer]::Ordinal)
        foreach ($key in $keyList) {
            $parts += '{0}:{1}' -f (ConvertTo-DomovoyCanonicalString -Text ([string]$key)), (Get-DomovoyCanonicalJson -Value $Value[$key] -Depth ($Depth + 1))
        }
        return '{' + ($parts -join ',') + '}'
    }

    if ($Value -is [System.Collections.IEnumerable]) {
        $parts = @()
        foreach ($item in $Value) {
            $parts += Get-DomovoyCanonicalJson -Value $item -Depth ($Depth + 1)
        }
        return '[' + ($parts -join ',') + ']'
    }

    if ($Value -is [PSObject]) {
        $parts = @()
        $propList = [System.Collections.Generic.List[string]]::new()
        foreach ($p in @($Value.PSObject.Properties)) { $propList.Add([string]$p.Name) }
        $propList.Sort([System.StringComparer]::Ordinal)
        foreach ($propName in $propList) {
            $prop = $Value.PSObject.Properties[$propName]
            $parts += '{0}:{1}' -f (ConvertTo-DomovoyCanonicalString -Text $prop.Name), (Get-DomovoyCanonicalJson -Value $prop.Value -Depth ($Depth + 1))
        }
        return '{' + ($parts -join ',') + '}'
    }

    # Fallback for any other leaf type (Guid, TimeSpan, ...): the invariant
    # string form. Honest and deterministic, unlike a silent type guess.
    return (ConvertTo-DomovoyCanonicalString -Text ([string]$Value))
}

function ConvertTo-DomovoyCanonicalString {
    # Minimal RFC 8259 escaping: quote, backslash and control characters.
    # Everything else (including non-ASCII) stays literal - the ledger file
    # is UTF-8 already, and parsing on the verify side normalizes any
    # escaping differences away before hashing.
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    $builder = New-Object System.Text.StringBuilder
    $null = $builder.Append('"')
    foreach ($ch in $Text.ToCharArray()) {
        switch ($ch) {
            '"' { $null = $builder.Append('\"') }
            '\' { $null = $builder.Append('\\') }
            "`b" { $null = $builder.Append('\b') }
            "`f" { $null = $builder.Append('\f') }
            "`n" { $null = $builder.Append('\n') }
            "`r" { $null = $builder.Append('\r') }
            "`t" { $null = $builder.Append('\t') }
            default {
                if ([int]$ch -lt 0x20) {
                    $null = $builder.Append('\u{0:x4}' -f [int]$ch)
                }
                else {
                    $null = $builder.Append($ch)
                }
            }
        }
    }
    $null = $builder.Append('"')
    return $builder.ToString()
}
