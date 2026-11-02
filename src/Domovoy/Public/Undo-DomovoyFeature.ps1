function Undo-DomovoyFeature {
    <#
    .SYNOPSIS
    Undoes a feature by restoring the exact state captured before its last apply.

    .DESCRIPTION
    Finds the most recent feature.apply event for the feature in the ledger and
    restores every captured value (registry values with their original types,
    service startup types, stopped services started again when they were
    running). Values that did not exist before the tweak are removed.
    Without -Apply the command is a dry-run: it shows what would be restored.

    .EXAMPLE
    Undo-DomovoyFeature -Id services.diagtrack.disabled

    .EXAMPLE
    Undo-DomovoyFeature -Id services.diagtrack.disabled -Apply
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$Id,

        [switch]$Apply
    )

    if (-not (Test-Path (Get-DomovoyStorePath -SubPath 'ledger.jsonl'))) {
        throw 'Ledger not found. Nothing to undo.'
    }

    $entry = Get-DomovoyLedger -FeatureId $Id -Event 'feature.apply' -Last 1000000 |
        Select-Object -Last 1

    if (-not $entry) {
        throw "No ledger entry to undo for: $Id"
    }

    # Dry-run by default (invariant I3).
    if (-not $Apply) {
        [pscustomobject]@{
            Feature = $Id
            Mode = 'DryRun'
            AppliedAt = $entry.timestamp
            Snapshot = $entry.snapshot
        }
        return
    }

    # Elevation is checked explicitly (invariant I5).
    if (-not (Test-DomovoyAdmin)) {
        throw 'Undo requires an elevated PowerShell session.'
    }

    if ($PSCmdlet.ShouldProcess($Id, 'Restore snapshot')) {
        # Catalog 75: machine-readable winget hints collected while undoing
        # appx packages whose files are gone (additive result field).
        $wingetHints = [System.Collections.Generic.List[object]]::new()
        foreach ($state in @($entry.snapshot)) {
            switch ($state.op) {
                'registry.set' {
                    if ($state.previousValue -eq '<unset>') {
                        Remove-ItemProperty -LiteralPath $state.path -Name $state.name -ErrorAction SilentlyContinue
                        # v0.3 (spec 9.1): when apply created the registry key itself,
                        # undo removes the now-empty leaf key and climbs up through
                        # empty ancestors so the pre-apply state is restored exactly.
                        if ($state.PSObject.Properties['pathExisted'] -and -not $state.pathExisted) {
                            $currentPath = $state.path
                            while ($currentPath -and (Test-Path -LiteralPath $currentPath)) {
                                $key = Get-Item -LiteralPath $currentPath
                                if (@($key.GetValueNames()).Count -ne 0 -or @($key.GetSubKeyNames()).Count -ne 0) {
                                    break
                                }
                                $parentPath = Split-Path -Parent $currentPath
                                Remove-Item -LiteralPath $currentPath -Force
                                if (-not $parentPath -or $parentPath -notmatch '^(HKLM|HKCU|HKCR|HKU):') {
                                    break
                                }
                                $currentPath = $parentPath
                            }
                        }
                    }
                    elseif ($state.previousType -and $state.previousType -ne 'None') {
                        $null = New-ItemProperty -LiteralPath $state.path -Name $state.name -Value $state.previousValue -PropertyType $state.previousType -Force
                    }
                    else {
                        $null = New-ItemProperty -LiteralPath $state.path -Name $state.name -Value $state.previousValue -Force
                    }
                }
                'appx.remove' {
                    # Re-register the package from its install location when the
                    # files are still on disk (documented mechanism, no network - I4).
                    $reRegistered = $false
                    if ($state.PSObject.Properties['installLocation']) {
                        $location = $state.installLocation
                        if ($location -and $location -ne '<missing>') {
                            $manifestPath = Join-Path -Path $location -ChildPath 'AppxManifest.xml'
                            if (Test-Path -LiteralPath $manifestPath) {
                                $null = Add-AppxPackage -Register $manifestPath -DisableDevelopmentMode -ErrorAction SilentlyContinue
                                $reRegistered = $true
                            }
                        }
                    }
                    if (-not $reRegistered) {
                        # Catalog 20 + 75: say honestly which documented source
                        # can restore the package, machine-readable when a
                        # confident winget id exists. Domovoy itself stays
                        # offline (I4).
                        $hint = Get-DomovoyWingetHint -PackageName $state.name
                        $wingetHints.Add(@{
                            Package = [string]$state.name
                            WingetId = $hint
                        })
                        if ($hint) {
                            Write-Warning ("appx.remove undo for '{0}': the package files are no longer on disk, so re-registering is not possible. Documented recovery: reinstall the app from Microsoft Store or winget (winget install --id '{1}')." -f $state.name, $hint)
                        }
                        else {
                            Write-Warning ("appx.remove undo for '{0}': the package files are no longer on disk, so re-registering is not possible. Documented recovery: reinstall the app from Microsoft Store or winget." -f $state.name)
                        }
                    }
                    # Provisioned removal is not restored; the post-undo
                    # verification reports this honestly instead of pretending.
                }
                'file.attribute' {
                    # -Force: the file stays Hidden until the restore below
                    # runs, and Get-Item cannot see a hidden file without it.
                    if ($state.PSObject.Properties['previousAttributes'] -and
                        $state.previousAttributes -ne '<missing>' -and
                        (Test-Path -LiteralPath $state.path)) {
                        $item = Get-Item -LiteralPath $state.path -Force
                        $target = [System.IO.FileAttributes]$state.previousAttributes
                        if ($item.Attributes -band [System.IO.FileAttributes]::Directory) {
                            # The Directory bit itself cannot be cleared; keep it.
                            $target = $target -bor [System.IO.FileAttributes]::Directory
                        }
                        $item.Attributes = $target
                    }
                }
                'registry.delete' {
                    # A deleted value is recreated with its exact type and data;
                    # if the value did not exist before apply, the absence is restored.
                    if ($state.previousType -and $state.previousType -ne 'None') {
                        if (-not (Test-Path -LiteralPath $state.path)) {
                            $null = New-Item -Path $state.path -ItemType Directory -Force
                        }
                        $null = New-ItemProperty -LiteralPath $state.path -Name $state.name -Value $state.previousValue -PropertyType $state.previousType -Force
                    }
                    elseif ($state.previousValue -eq '<unset>') {
                        Remove-ItemProperty -LiteralPath $state.path -Name $state.name -ErrorAction SilentlyContinue
                    }
                }
                'service.startup' {
                    if ($state.previousValue -ne '<missing>') {
                        Set-Service -Name $state.name -StartupType $state.previousValue
                    }
                }
                'service.stop' {
                    if ($state.previousStatus -eq 'Running') {
                        Start-Service -Name $state.name -ErrorAction SilentlyContinue
                    }
                    elseif ($state.previousStatus -eq 'Stopped') {
                        $current = Get-Service -Name $state.name -ErrorAction SilentlyContinue
                        if ($current -and $current.Status -eq 'Running') {
                            Stop-Service -Name $state.name -Force -ErrorAction SilentlyContinue
                        }
                    }
                }
                'network.dns' {
                    if ($state.PSObject.Properties['previousServers'] -and @($state.previousServers).Count -gt 0) {
                        $null = Set-DnsClientServerAddress -InterfaceAlias $state.interfaceAlias -ServerAddresses @($state.previousServers) -ErrorAction SilentlyContinue
                    }
                    else {
                        # No explicit servers before the tweak: reset back to
                        # the DHCP defaults (the documented way to clear them).
                        $null = Set-DnsClientServerAddress -InterfaceAlias $state.interfaceAlias -ResetServerAddresses -ErrorAction SilentlyContinue
                    }
                }
                'network.proxy' {
                    # Restore the four WinINET values exactly as captured;
                    # '<unset>' means the value did not exist before the apply.
                    $proxyKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
                    if (-not (Test-Path -LiteralPath $proxyKey)) {
                        $null = New-Item -Path $proxyKey -ItemType Directory -Force
                    }
                    $undoValues = @(
                        @{ Name = 'ProxyEnable';   Previous = $state.previousProxyEnable;   Type = 'DWord' }
                        @{ Name = 'ProxyServer';   Previous = $state.previousProxyServer;   Type = 'String' }
                        @{ Name = 'AutoConfigURL'; Previous = $state.previousAutoConfigUrl; Type = 'String' }
                        @{ Name = 'ProxyOverride'; Previous = $state.previousProxyOverride; Type = 'String' }
                    )
                    foreach ($value in $undoValues) {
                        if ($value.Previous -eq '<unset>') {
                            Remove-ItemProperty -LiteralPath $proxyKey -Name $value.Name -ErrorAction SilentlyContinue
                        }
                        else {
                            $null = New-ItemProperty -LiteralPath $proxyKey -Name $value.Name -Value $value.Previous -PropertyType $value.Type -Force
                        }
                    }
                }
                'scheduler.task' {
                    # The task is only re-enabled if it was enabled before the
                    # tweak; a task deleted by someone else is not recreated.
                    if ($state.previousState -ne '<missing>' -and $state.previousState -ne 'Disabled') {
                        $task = Get-ScheduledTask -TaskPath $state.taskPath -TaskName $state.taskName -ErrorAction SilentlyContinue
                        if ($task -and $task.State -eq 'Disabled') {
                            $null = Enable-ScheduledTask -TaskPath $state.taskPath -TaskName $state.taskName -ErrorAction SilentlyContinue
                        }
                    }
                }
                'file.timestamp' {
                    # '<missing>' for every stamp means the file did not
                    # exist before the apply - undo keeps the absence.
                    if ($state.previousCreation -ne '<missing>' -and (Test-Path -LiteralPath $state.path)) {
                        foreach ($pair in @(
                            @{ Field = 'creation';   Previous = $state.previousCreation }
                            @{ Field = 'lastWrite';  Previous = $state.previousLastWrite }
                            @{ Field = 'lastAccess'; Previous = $state.previousLastAccess }
                        )) {
                            if ($pair.Previous -and $pair.Previous -ne '<missing>') {
                                Set-DomovoyTimestamp -Path $state.path -Field $pair.Field -Value $pair.Previous
                            }
                        }
                    }
                }
                'shell.handler.remove' {
                    # The exact registration captured before the apply is
                    # recreated; if it did not exist, the absence is restored.
                    if ($state.keyExisted -and $null -ne $state.tree) {
                        if (Test-Path -LiteralPath $state.key) {
                            Remove-Item -LiteralPath $state.key -Recurse -Force
                        }
                        $parent = Split-Path -Parent ([string]$state.key)
                        Restore-DomovoyRegKeyTree -Tree $state.tree -ParentPath $parent
                    }
                    elseif (Test-Path -LiteralPath $state.key) {
                        Remove-Item -LiteralPath $state.key -Recurse -Force
                    }
                }
                'shell.handler.block' {
                    $blockedKey = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked'
                    if ($state.previousValue -eq '<unset>') {
                        Remove-ItemProperty -LiteralPath $blockedKey -Name ([string]$state.clsid) -ErrorAction SilentlyContinue
                    }
                    elseif (Test-Path -LiteralPath $blockedKey) {
                        $null = New-ItemProperty -LiteralPath $blockedKey -Name ([string]$state.clsid) -Value $state.previousValue -PropertyType String -Force
                    }
                }
                'shell.openwith.remove' {
                    $owKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\{0}\{1}' -f $state.extension, $state.kind
                    if ($state.kind -eq 'OpenWithList') {
                        # Restore the exact removed letters and the exact
                        # MRUList string captured before the apply.
                        foreach ($removed in @($state.removedLetters)) {
                            $null = New-ItemProperty -LiteralPath $owKey -Name ([string]$removed.letter) -Value ([string]$removed.data) -PropertyType String -Force
                        }
                        if ($state.PSObject.Properties['mruExisted']) {
                            if ($state.mruExisted) {
                                $null = New-ItemProperty -LiteralPath $owKey -Name 'MRUList' -Value ([string]$state.previousMrulist) -PropertyType String -Force
                            }
                            else {
                                Remove-ItemProperty -LiteralPath $owKey -Name 'MRUList' -ErrorAction SilentlyContinue
                            }
                        }
                    }
                    else {
                        if ($state.valueExisted) {
                            if (-not (Test-Path -LiteralPath $owKey)) {
                                $null = New-Item -Path $owKey -ItemType Directory -Force
                            }
                            $kindName = [string]$state.previousKind
                            $kind = [Microsoft.Win32.RegistryValueKind]::String
                            if (-not [Enum]::TryParse([Microsoft.Win32.RegistryValueKind], $kindName, $true, [ref]$kind)) {
                                $kind = [Microsoft.Win32.RegistryValueKind]::String
                            }
                            $restoreData = [string]$state.previousData
                            switch ($kind.ToString()) {
                                'Binary'      { $restoreData = [Convert]::FromBase64String([string]$state.previousData) }
                                'MultiString' { $restoreData = [string[]]@($state.previousData | ForEach-Object { [string]$_ }) }
                                'DWord'       { $restoreData = [int]$state.previousData }
                                'QWord'       { $restoreData = [long]$state.previousData }
                            }
                            try {
                                # New-ItemProperty opens the key with write
                                # access; a raw Get-Item handle is read-only
                                # and SetValue on it fails (E2E, run 38).
                                $null = New-ItemProperty -LiteralPath $owKey -Name ([string]$state.entry) -Value $restoreData -PropertyType $kind -Force
                            }
                            catch {
                                # A None/Unknown kind cannot be stored back
                                # as-is; the closest honest spelling is String.
                                Write-Warning ("shell.openwith.remove undo: the exact value kind '{0}' could not be restored, the entry was recreated as String." -f $kindName)
                                $null = New-ItemProperty -LiteralPath $owKey -Name ([string]$state.entry) -Value ([string]$state.previousData) -PropertyType String -Force
                            }
                        }
                        elseif (Test-Path -LiteralPath $owKey) {
                            Remove-ItemProperty -LiteralPath $owKey -Name ([string]$state.entry) -ErrorAction SilentlyContinue
                        }
                    }
                }
            }
        }

        $verification = $null
        try {
            $manifest = Get-DomovoyManifestForFeature -Id $Id -LedgerEntry $entry
            $verification = Test-DomovoyEffect -Manifest $manifest
        }
        catch {
            Write-Verbose ("Post-undo verification was not possible: {0}" -f $_.Exception.Message)
        }
        $written = Write-DomovoyLedgerEntry -Entry @{
            event = 'feature.undo'
            featureId = $Id
            verification = $verification
        }

        [pscustomobject]@{
            Feature = $Id
            Mode = 'Undo'
            Verification = $verification
            WingetHints = @($wingetHints)
            LedgerTimestamp = $written['timestamp']
        }
    }
}
