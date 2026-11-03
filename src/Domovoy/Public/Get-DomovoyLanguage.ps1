function Get-DomovoyLanguage {
    <#
    .SYNOPSIS
    Reports the active presentation language of Domovoy (v1.6 item 6).

    .DESCRIPTION
    Read-only. Answers three questions honestly: which language the strings
    table resolves to right now, where that decision came from (an explicit
    session override, the stored preference file, or the built-in default),
    and where the preference file lives. The language affects only the GUI
    and the human summaries of the key reports - never which commands run,
    never the ledger, never the system state.

    .EXAMPLE
    Get-DomovoyLanguage

    .EXAMPLE
    Get-DomovoyLanguage | Select-Object -ExpandProperty Language
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $session = $null
    if ($script:DomovoyLanguage) {
        $session = [string]$script:DomovoyLanguage
    }

    $prefFile = $null
    $stored = $null
    try {
        $prefFile = Join-Path -Path (Get-DomovoyStorePath) -ChildPath 'language.txt'
        if (Test-Path -LiteralPath $prefFile) {
            $first = (Get-Content -LiteralPath $prefFile -Encoding UTF8 -ErrorAction Stop | Select-Object -First 1)
            if ($first) { $stored = ([string]$first).Trim().ToLowerInvariant() }
        }
    }
    catch {
        # A broken store is reported honestly, not silently ignored.
        $prefFile = $null
        $stored = $null
    }

    $active = if ($session) { $session } elseif ($stored) { $stored } else { 'en' }
    if (@('en', 'ru') -notcontains $active) { $active = 'en' }

    $source = if ($session) { 'session' } elseif ($stored -and @('en', 'ru') -contains $stored) { 'store' } else { 'default' }

    [pscustomobject]@{
        Language = $active
        Source = $source
        PreferenceFile = $prefFile
    }
}
