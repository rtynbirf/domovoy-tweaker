function Invoke-DomovoyCleanup {
    <#
    .SYNOPSIS
    Shows how much space a cleanup would free (dry-run by default) or removes
    old temporary files of the current user.

    .DESCRIPTION
    Catalog feature 37: first the report ("how much will be freed"), then -
    only with -Apply - the deletion. Only regular files in the current user's
    temporary directory that have not been modified for the given number of
    days are touched.

    The action is irreversible: deleted temporary files cannot be restored,
    so this command is deliberately not a feature manifest and creates no undo
    snapshot (spec 5.1). Instead, the fact of the cleanup is appended to the
    ledger as a cleanup.apply event. Files that cannot be deleted (locked by a
    running process) are counted honestly as failed, not silently skipped.

    .EXAMPLE
    Invoke-DomovoyCleanup -Target Temp -OlderThanDays 7

    .EXAMPLE
    Invoke-DomovoyCleanup -Target Temp -OlderThanDays 7 -Apply

    .EXAMPLE
    Invoke-DomovoyCleanup -Target ThumbCache
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [ValidateSet('Temp', 'ThumbCache')]
        [string]$Target = 'Temp',

        [ValidateRange(0, 3650)]
        [int]$OlderThanDays = 7,

        [switch]$Apply
    )

    $fileFilter = $null
    if ($Target -eq 'Temp') {
        $paths = @([System.IO.Path]::GetTempPath())
    }
    elseif ($Target -eq 'ThumbCache') {
        # Catalog 89: the Explorer thumbnail cache directory. Only the
        # documented thumbcache_*.db files belong to the cache; everything
        # else in the directory stays untouched.
        $paths = @(Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Microsoft\Windows\Explorer')
        $fileFilter = 'thumbcache_*.db'
    }

    $cutoff = (Get-Date).AddDays(-1 * $OlderThanDays)

    $candidates = @(Get-ChildItem -LiteralPath $paths -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object { ($_.LastWriteTime -lt $cutoff) -and ((-not $fileFilter) -or ($_.Name -like $fileFilter)) })

    $bytes = [long]0
    foreach ($file in $candidates) {
        $bytes += [long]$file.Length
    }

    # Dry-run by default (invariant I3).
    if (-not $Apply) {
        [pscustomobject]@{
            Target = $Target
            Mode = 'DryRun'
            Paths = $paths
            OlderThanDays = $OlderThanDays
            Files = $candidates.Count
            Bytes = $bytes
        }
        return
    }

    if ($PSCmdlet.ShouldProcess(($paths -join '; '), ("Remove {0} temporary files older than {1} days" -f $candidates.Count, $OlderThanDays))) {
        $removed = 0
        $removedBytes = [long]0
        $failed = 0
        foreach ($file in $candidates) {
            try {
                Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
                $removed++
                $removedBytes += [long]$file.Length
            }
            catch {
                # Locked or permission-blocked files are reported honestly.
                $failed++
            }
        }

        # Measured "after": re-scan what is left instead of deriving it from
        # arithmetic (catalog feature 44 - the report must be measurable).
        $remaining = @(Get-ChildItem -LiteralPath $paths -Recurse -File -Force -ErrorAction SilentlyContinue |
            Where-Object { ($_.LastWriteTime -lt $cutoff) -and ((-not $fileFilter) -or ($_.Name -like $fileFilter)) })
        $bytesAfter = [long]0
        foreach ($file in $remaining) {
            $bytesAfter += [long]$file.Length
        }

        $written = Write-DomovoyLedgerEntry -Entry @{
            event = 'cleanup.apply'
            featureId = 'cleanup.' + $Target.ToLowerInvariant()
            target = $Target
            olderThanDays = $OlderThanDays
            filesFound = $candidates.Count
            bytesFound = $bytes
            filesRemoved = $removed
            bytesFreed = $removedBytes
            filesFailed = $failed
            bytesAfter = $bytesAfter
            irreversible = $true
        }

        [pscustomobject]@{
            Target = $Target
            Mode = 'Apply'
            FilesFound = $candidates.Count
            BytesFound = $bytes
            FilesRemoved = $removed
            BytesFreed = $removedBytes
            FilesFailed = $failed
            BytesAfter = $bytesAfter
            LedgerTimestamp = $written['timestamp']
        }
    }
}
