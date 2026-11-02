function Get-DomovoyLedgerSchemaVersion {
    <#
    .SYNOPSIS
    Returns the journal schema version this module writes and understands.
    Private single source of truth (catalog 101).

    .DESCRIPTION
    Schema 1 is the only schema that exists so far (additive format, SemVer
    MAJOR policy). When a future release defines schema 2, this number moves
    together with a documented migration rule - the writer, the inventory
    and the migration command all read the version from here.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param()

    return 1
}

function Get-DomovoyLedgerMigrationRule {
    <#
    .SYNOPSIS
    Returns the migration rule for one journal schema step, or $null when no
    rule is defined. Private helper of Invoke-DomovoyLedgerMigration.

    .DESCRIPTION
    A rule is a hashtable: From, To and Transform (a scriptblock that
    receives one parsed entry and mutates it in place). Deliberately empty
    today: schema 2 does not exist, so inventing a transformation would be a
    lie. The release that defines schema 2 registers its rule here, and the
    mechanism - backup, rewrite, chain rebuild, audit entry - is already
    shipped and tested.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [int]$From,

        [Parameter(Mandatory)]
        [int]$To
    )

    # A rule must describe a real step forward; a nonsensical step is
    # answered with "no rule" instead of inventing a transformation.
    if ($From -lt 1 -or $To -le $From) {
        return $null
    }

    # No transformation is defined yet: schema 2 does not exist, and
    # inventing one would be a lie. The release that defines schema 2
    # returns its rule here - the mechanism around it is already shipped
    # and tested.
    return $null
}
