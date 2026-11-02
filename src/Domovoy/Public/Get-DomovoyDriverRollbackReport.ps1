function Get-DomovoyDriverRollbackReport {
    <#
    .SYNOPSIS
    Reports which third-party drivers in the driver store still have an older
    package in place - i.e. which ones are actually ready to roll back.
    Read-only, changes nothing.

    .DESCRIPTION
    Catalog feature 90: "the driver is ready for rollback" report. Windows
    keeps every third-party driver package ever installed in the DriverStore
    (C:\Windows\DriverStore\FileRepository). A driver can only be rolled back
    when an older package of the same original INF is still in the store; the
    pnputil-style oem history is read here through the documented
    Get-WindowsDriver cmdlet (the built-in DISM module - no external process,
    invariant I4 holds).

    The report groups packages by their original INF name, compares versions
    and answers per group: the active (newest) version, the older packages
    that would take over on a rollback, and the honest RollbackReady verdict.
    A driver with a single package in the store is reported as not ready -
    that is a fact, not an error.

    .EXAMPLE
    Get-DomovoyDriverRollbackReport
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    # -Online asks the running OS for the full driver-store table. The call
    # needs elevation on a real machine; without it the error propagates -
    # an honest failure, not an empty report.
    $packages = @(Get-WindowsDriver -Online -ErrorAction Stop |
        Where-Object { -not $_.Inbox } |
        Select-Object Driver, OriginalFileName, ClassName, ProviderName, Date, Version)

    $groups = @{}
    foreach ($package in $packages) {
        $leaf = [System.IO.Path]::GetFileName([string]$package.OriginalFileName)
        if (-not $leaf) { $leaf = [string]$package.Driver }
        if (-not $groups.ContainsKey($leaf)) {
            $groups[$leaf] = @()
        }
        $groups[$leaf] += $package
    }

    $rows = @()
    foreach ($leaf in ($groups.Keys | Sort-Object)) {
        $members = @($groups[$leaf])
        # Rank by version, then by date - both documented package attributes.
        $sorted = @($members | Sort-Object -Property @{ Expression = { [version]$_.Version }; Descending = $true }, @{ Expression = { $_.Date }; Descending = $true })
        $active = $sorted[0]
        $older = @()
        if ($sorted.Count -gt 1) {
            $older = @($sorted | Select-Object -Skip 1)
        }
        $rows += [pscustomobject]@{
            InfName = $leaf
            ClassName = [string]$active.ClassName
            ProviderName = [string]$active.ProviderName
            ActiveOemDriver = [string]$active.Driver
            ActiveVersion = [string]$active.Version
            ActiveDate = $active.Date
            OlderPackages = @($older | ForEach-Object {
                '{0} {1} ({2})' -f $_.Driver, $_.Version, ([string]$_.Date)
            })
            RollbackReady = (@($older).Count -gt 0)
        }
    }

    $ready = @($rows | Where-Object { $_.RollbackReady })

    [pscustomobject]@{
        DriverPackages = @($packages).Count
        DriverGroups = @($rows).Count
        RollbackReady = @($ready).Count
        Groups = $rows
        Note = 'Rollback-ready means an older third-party package of the same original INF is still in the driver store. Read-only: nothing was changed.'
    }
}
