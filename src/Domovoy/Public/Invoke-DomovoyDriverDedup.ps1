function Invoke-DomovoyDriverDedup {
    <#
    .SYNOPSIS
    Shows duplicate old driver store copies (dry-run by default) or removes
    them - but only after a full .cab backup of every third-party driver.

    .DESCRIPTION
    Catalog feature 43 (and 46, the full driver dump): Modern Tweaker 3.0's
    RemoveDubOldDrivers removed old driver copies without ceremony; here the
    backup gate comes first and is absolute. With -Apply the command exports
    every third-party driver (pnputil /export-driver *), packs the export
    into one .cab in the Domovoy store (or -BackupDirectory), and only then
    removes the old duplicates. If the backup fails, NOTHING is removed.

    Duplicates are oem*.inf store entries sharing the same provider, class
    and original INF name; the newest version is kept. Removal runs without
    /force: a driver that is in use refuses removal and is reported as
    failed, not deleted.

    Requires elevation on both paths (invariant I5).

    .PARAMETER BackupDirectory
    Where the .cab backup is written (default: the Domovoy store backups
    folder).

    .EXAMPLE
    Invoke-DomovoyDriverDedup

    .EXAMPLE
    Invoke-DomovoyDriverDedup -Apply
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [string]$BackupDirectory,

        [switch]$Apply
    )

    if (-not (Test-DomovoyAdmin)) {
        throw 'Driver enumeration requires an elevated PowerShell session.'
    }

    $all = @(Get-WindowsDriver -Online -ErrorAction Stop)

    # Third-party driver store entries sharing provider + class + original
    # INF name are duplicate store copies of one driver.
    $groups = @($all |
        Group-Object -Property ProviderName, ClassGuid, OriginalFileName |
        Where-Object { $_.Count -gt 1 })

    $candidates = @()
    foreach ($group in $groups) {
        $sorted = @($group.Group |
            Sort-Object -Property @{ Expression = { [version]$_.Version } }, @{ Expression = { $_.Date } } -Descending)
        $keep = $sorted[0]
        foreach ($old in @($sorted | Select-Object -Skip 1)) {
            $candidates += [pscustomobject]@{
                Driver = $old.Driver
                OriginalFileName = $old.OriginalFileName
                ProviderName = $old.ProviderName
                ClassName = $old.ClassName
                Version = $old.Version
                Date = $old.Date
                KeepDriver = $keep.Driver
                KeepVersion = $keep.Version
            }
        }
    }

    # Dry-run by default (invariant I3).
    if (-not $Apply) {
        [pscustomobject]@{
            Mode = 'DryRun'
            DriversScanned = $all.Count
            DuplicateGroups = $groups.Count
            Candidates = $candidates
            Note = 'Removal happens only after a full .cab backup of every third-party driver (catalog 43).'
        }
        return
    }

    if ($PSCmdlet.ShouldProcess('driver store', 'Backup third-party drivers, then remove duplicate old copies')) {
        if ($candidates.Count -eq 0) {
            [pscustomobject]@{
                Mode = 'Apply'
                Removed = @()
                Failed = @()
                BackupCab = $null
                Note = 'No duplicate old drivers found; nothing was removed and no backup was needed.'
            }
            return
        }

        # 1. The backup gate (catalog 43): full export of every third-party
        #    driver, packed into one .cab, verified to exist. Failure here
        #    means nothing is removed.
        $backupRoot = if ([string]::IsNullOrEmpty($BackupDirectory)) {
            Get-DomovoyStorePath -SubPath 'backups'
        }
        else {
            $BackupDirectory
        }
        $exportDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath (
            "domovoy-driver-export-" + [guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $exportDir -Force

        try {
            $null = & pnputil /export-driver '*' $exportDir
            if ($LASTEXITCODE -ne 0) {
                throw ("pnputil /export-driver failed (exit {0}). Nothing was removed." -f $LASTEXITCODE)
            }
            $exported = @(Get-ChildItem -LiteralPath $exportDir -Recurse -File)
            if ($exported.Count -eq 0) {
                throw 'Driver export produced no files. Nothing was removed.'
            }

            $cabPath = Join-Path -Path $backupRoot -ChildPath (
                "driver-backup-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + ".cab")
            $null = ConvertTo-DomovoyCab -SourceDirectory $exportDir -DestinationFile $cabPath
        }
        finally {
            Remove-Item -LiteralPath $exportDir -Recurse -Force -ErrorAction SilentlyContinue
        }

        # 2. Remove old copies WITHOUT /force: a driver that is in use
        #    refuses removal and lands in the honest failed list.
        $removed = @()
        $failed = @()
        foreach ($candidate in $candidates) {
            $null = & pnputil /delete-driver $candidate.Driver
            if ($LASTEXITCODE -eq 0) {
                $removed += $candidate.Driver
            }
            else {
                $failed += @{
                    driver = $candidate.Driver
                    exitCode = $LASTEXITCODE
                }
            }
        }

        $written = Write-DomovoyLedgerEntry -Entry @{
            event = 'driverdedup.apply'
            backupCab = $cabPath
            backupFiles = $exported.Count
            removed = @($removed)
            failed = @($failed)
        }

        [pscustomobject]@{
            Mode = 'Apply'
            BackupCab = $cabPath
            BackupFiles = $exported.Count
            Removed = @($removed)
            Failed = @($failed)
            LedgerTimestamp = $written['timestamp']
        }
    }
}
