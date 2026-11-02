function Get-DomovoyBitLockerStatus {
    <#
    .SYNOPSIS
    Shows the BitLocker protection state of every volume. Read-only, changes
    nothing.

    .DESCRIPTION
    Catalog feature 49: the BitLocker state is displayed, never toggled.
    Toggling protection belongs to dedicated tooling, not to a tweaker.
    Querying BitLocker requires an elevated session; without elevation the
    command fails with an explicit message (invariant I5).

    .EXAMPLE
    Get-DomovoyBitLockerStatus
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    if (-not (Test-DomovoyAdmin)) {
        throw 'BitLocker status requires an elevated PowerShell session.'
    }

    if (-not (Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue)) {
        throw 'The BitLocker module is not available on this Windows edition.'
    }

    $rows = @()
    foreach ($volume in @(Get-BitLockerVolume)) {
        $rows += [pscustomobject]@{
            MountPoint = $volume.MountPoint
            VolumeStatus = [string]$volume.VolumeStatus
            ProtectionStatus = [string]$volume.ProtectionStatus
            EncryptionPercentage = $volume.EncryptionPercentage
            KeyProtectorCount = @($volume.KeyProtector).Count
        }
    }

    return @($rows)
}
