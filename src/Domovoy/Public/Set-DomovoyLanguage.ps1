function Set-DomovoyLanguage {
    <#
    .SYNOPSIS
    Switches the presentation language of Domovoy between 'en' and 'ru'
    (v1.6 item 6).

    .DESCRIPTION
    Sets the language used by the GUI and the human summaries of the key
    reports. The switch is immediate for the current session and is also
    written to the preference file <store>\language.txt so the next session
    starts in the chosen language. It deliberately does NOT touch the
    system, the registry or the journal: this is a module preference, not a
    machine state change, so there is no dry-run/apply contour and no
    ledger event - the invariants I1-I7 guard system state, and a UI
    language is not that.

    If the store is read-only or unavailable, the command says so honestly:
    the language still switches for this session, the persistence is
    reported as not written, and the exit code stays green because the
    session switch succeeded.

    The catalog titles, the CLI help and the machine-readable report fields
    stay in English - the ledger schema and the feature manifests are
    frozen formats (spec section 10), and their texts are part of the
    documented contract.

    .PARAMETER Language
    'en' or 'ru'.

    .EXAMPLE
    Set-DomovoyLanguage -Language ru

    .EXAMPLE
    Set-DomovoyLanguage -Language en
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('en', 'ru')]
        [string]$Language
    )

    $previous = (Get-DomovoyLanguage).Language
    $script:DomovoyLanguage = $Language.ToLowerInvariant()

    $prefFile = $null
    $persisted = $false
    $note = $null
    try {
        $prefFile = Join-Path -Path (Get-DomovoyStorePath) -ChildPath 'language.txt'
        [System.IO.File]::WriteAllText($prefFile, $script:DomovoyLanguage + [Environment]::NewLine,
            [System.Text.UTF8Encoding]::new($false))
        $persisted = $true
    }
    catch {
        $persisted = $false
        $note = 'the preference file could not be written ({0}); the language is switched for this session only' -f $_.Exception.Message
    }

    [pscustomobject]@{
        Previous = $previous
        Language = $script:DomovoyLanguage
        Persisted = $persisted
        PreferenceFile = $prefFile
        Note = $note
    }
}
