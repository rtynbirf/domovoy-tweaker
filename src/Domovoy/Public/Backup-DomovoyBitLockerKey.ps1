function Backup-DomovoyBitLockerKey {
    <#
    .SYNOPSIS
    Shows which recovery keys exist (dry-run by default) or writes the
    BitLocker recovery key of one volume to an explicit user-chosen file.

    .DESCRIPTION
    Catalog feature 50: a backup of the BitLocker recovery key, made only on
    an explicit user request with an explicit output path. Honesty rules:
    the recovery password is written ONLY to the output file and NEVER to
    the ledger (the journal event records the volume, the key protector id
    and the output path, not the key) and NEVER to the command output.
    The output file is ACL-restricted to the current user where the file
    system supports it.

    Requires elevation (Get-BitLockerVolume needs it, invariant I5).

    .PARAMETER MountPoint
    Volume mount point, for example 'C:'.

    .PARAMETER OutFile
    Explicit output path for the key file.

    .EXAMPLE
    Backup-DomovoyBitLockerKey -MountPoint 'C:' -OutFile 'D:\keys\c-recovery.txt'

    .EXAMPLE
    Backup-DomovoyBitLockerKey -MountPoint 'C:' -OutFile 'D:\keys\c-recovery.txt' -Apply
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$MountPoint,

        [Parameter(Mandatory)]
        [string]$OutFile,

        [switch]$Apply
    )

    # Get-BitLockerVolume requires elevation for reading too.
    if (-not (Test-DomovoyAdmin)) {
        throw 'BitLocker key backup requires an elevated PowerShell session.'
    }

    $volume = Get-BitLockerVolume -MountPoint $MountPoint -ErrorAction SilentlyContinue
    if (-not $volume) {
        throw ("No BitLocker volume found: {0}" -f $MountPoint)
    }

    $protectors = @($volume.KeyProtector |
        Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' })

    # Dry-run by default (invariant I3): show protectors without the key.
    if (-not $Apply) {
        [pscustomobject]@{
            Mode = 'DryRun'
            MountPoint = $MountPoint
            VolumeName = $volume.VolumeStatus
            RecoveryProtectors = $protectors.Count
            KeyProtectorIds = @($protectors | ForEach-Object { $_.KeyProtectorId })
            OutFile = $OutFile
            Note = 'The recovery password goes only to the output file - never to the ledger or to this output.'
        }
        return
    }

    if ($protectors.Count -eq 0) {
        throw ("Volume {0} has no recovery password protector; there is nothing to back up." -f $MountPoint)
    }

    if ($PSCmdlet.ShouldProcess($OutFile, "Write the BitLocker recovery key of $MountPoint")) {
        $protector = $protectors[0]

        $lines = @(
            'Domovoy BitLocker recovery key backup'
            ('MountPoint: {0}' -f $MountPoint)
            ('VolumeStatus: {0}' -f $volume.VolumeStatus)
            ('KeyProtectorId: {0}' -f $protector.KeyProtectorId)
            ('RecoveryPassword: {0}' -f $protector.RecoveryPassword)
            ('Created: {0}' -f ([DateTimeOffset]::UtcNow.ToString('o')))
        )
        Set-Content -LiteralPath $OutFile -Value $lines -Encoding ASCII

        # Restrict the key file to the current user where the file system
        # supports ACLs (best effort, reported honestly).
        $aclNote = 'restricted to the current user'
        try {
            $fileInfo = [System.IO.FileInfo]::new($OutFile)
            $security = $fileInfo.GetAccessControl()
            $security.SetAccessRuleProtection($true, $false)
            $me = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            $rule = [System.Security.AccessControl.FileSystemAccessRule]::new(
                $me, 'FullControl', 'Allow')
            $security.AddAccessRule($rule)
            $fileInfo.SetAccessControl($security)
        }
        catch {
            $aclNote = 'could not be restricted ({0})' -f $_.Exception.Message
        }

        # The key itself is never recorded here or in the ledger.
        $written = Write-DomovoyLedgerEntry -Entry @{
            event = 'bitlocker.keybackup'
            mountPoint = $MountPoint
            keyProtectorId = $protector.KeyProtectorId
            outFile = $OutFile
        }

        [pscustomobject]@{
            Mode = 'Apply'
            MountPoint = $MountPoint
            KeyProtectorId = $protector.KeyProtectorId
            OutFile = $OutFile
            AccessNote = $aclNote
            LedgerTimestamp = $written['timestamp']
        }
    }
}
