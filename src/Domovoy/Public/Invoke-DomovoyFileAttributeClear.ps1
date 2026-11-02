function Invoke-DomovoyFileAttributeClear {
    <#
    .SYNOPSIS
    Shows the plan (dry-run by default) or clears explicit attributes from
    explicit files/folders, recording the previous attributes in the ledger.

    .DESCRIPTION
    Catalog feature 47: the inverse of the file.attribute operation. Modern
    Tweaker's Attrib_off switched Explorer settings to reveal hidden files;
    this command works on explicit user-chosen paths instead and is honest
    about it: the full previous attribute set of every path is stored in the
    ledger and can be restored with Undo-DomovoyFileAttributeClear.

    Only the listed attributes are cleared; everything else (including the
    Directory bit and any attributes not listed) stays untouched.

    .PARAMETER Path
    One or more existing files or folders.

    .PARAMETER Attributes
    Attributes to clear (ReadOnly, Hidden, System, Archive, NotContentIndexed).

    .EXAMPLE
    Invoke-DomovoyFileAttributeClear -Path 'C:\temp\file.txt' -Attributes Hidden

    .EXAMPLE
    Invoke-DomovoyFileAttributeClear -Path 'C:\temp\file.txt' -Attributes Hidden -Apply
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string[]]$Path,

        [Parameter(Mandatory)]
        [ValidateSet('ReadOnly', 'Hidden', 'System', 'Archive', 'NotContentIndexed')]
        [string[]]$Attributes,

        [switch]$Apply
    )

    $items = @()
    foreach ($p in $Path) {
        if (-not (Test-Path -LiteralPath $p)) {
            throw ("Path not found: {0}" -f $p)
        }
        # -Force: a Hidden file is invisible to Get-Item without it.
        $items += @(Get-Item -LiteralPath $p -Force)
    }

    # Build the plan: what is present now and what would be cleared.
    $plan = @()
    foreach ($item in $items) {
        $present = @()
        foreach ($attrName in $Attributes) {
            if (($item.Attributes -band [System.IO.FileAttributes]::$attrName) -ne 0) {
                $present += $attrName
            }
        }
        $plan += [pscustomobject]@{
            Path = $item.FullName
            CurrentAttributes = [string]$item.Attributes
            WouldClear = ($present -join ',')
        }
    }

    # Dry-run by default (invariant I3).
    if (-not $Apply) {
        [pscustomobject]@{
            Mode = 'DryRun'
            Plan = $plan
        }
        return
    }

    if ($PSCmdlet.ShouldProcess(($items.FullName -join ', '), "Clear attributes: $($Attributes -join ', ')")) {
        $snapshot = @()
        $cleared = 0
        foreach ($item in $items) {
            $previous = [string]$item.Attributes
            $attrValue = [int]$item.Attributes
            foreach ($attrName in $Attributes) {
                $attrValue = $attrValue -band (-bnot [int][System.IO.FileAttributes]::$attrName)
            }
            $item.Attributes = [System.IO.FileAttributes]$attrValue
            $snapshot += @{
                path = $item.FullName
                previousAttributes = $previous
            }
            $cleared++
        }

        # Verify: re-read from disk, none of the cleared flags may remain.
        $verified = $true
        foreach ($entry in $snapshot) {
            $item = Get-Item -LiteralPath $entry.path -Force
            foreach ($attrName in $Attributes) {
                if (($item.Attributes -band [System.IO.FileAttributes]::$attrName) -ne 0) {
                    $verified = $false
                }
            }
        }

        $written = Write-DomovoyLedgerEntry -Entry @{
            event = 'fileattr.clear'
            attributes = @($Attributes)
            cleared = $cleared
            verified = $verified
            snapshot = $snapshot
        }

        [pscustomobject]@{
            Mode = 'Apply'
            Attributes = @($Attributes)
            Cleared = $cleared
            Verified = $verified
            LedgerTimestamp = $written['timestamp']
        }
    }
}
