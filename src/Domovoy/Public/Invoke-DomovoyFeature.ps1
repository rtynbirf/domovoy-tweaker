function Invoke-DomovoyFeature {
    <#
    .SYNOPSIS
    Shows the plan (dry-run by default) or applies a Domovoy feature.

    .DESCRIPTION
    Dry-run is the default: without -Apply the command returns the plan with the
    current state and changes nothing. With -Apply it requires elevation, creates
    a system restore point (soft), captures a snapshot of the current state,
    executes the manifest operations, runs verification probes and appends a
    feature.apply event to the ledger.

    .EXAMPLE
    Invoke-DomovoyFeature -Id services.diagtrack.disabled

    .EXAMPLE
    Invoke-DomovoyFeature -Id services.diagtrack.disabled -Apply
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ById')]
        [string]$Id,

        [Parameter(Mandatory, ParameterSetName = 'ByFile')]
        [string]$ManifestFile,

        [switch]$Apply,

        [switch]$SkipRestorePoint
    )

    $manifestPath = $null
    if ($PSCmdlet.ParameterSetName -eq 'ByFile') {
        $manifest = Read-FeatureManifest -Path $ManifestFile
        $manifestPath = $ManifestFile
    }
    else {
        $feature = Get-DomovoyFeature -Id $Id
        if ($feature) {
            $manifest = Read-FeatureManifest -Path $feature[0].File
            $manifestPath = $feature[0].File
        }
        else {
            # Not in the catalog: fall back to the manifest recorded in the
            # ledger (v0.2 featureSource invariant), the same resolution rule
            # Undo-DomovoyFeature uses. Auto-heal relies on this for features
            # that were applied from external manifest files.
            $lastApply = @(Get-DomovoyLedger -FeatureId $Id -Event 'feature.apply' -Last 1000000) |
                Select-Object -Last 1
            if (-not $lastApply -or
                -not $lastApply.featureSource -or
                -not (Test-Path -LiteralPath $lastApply.featureSource)) {
                throw "Feature not found: $Id"
            }
            $manifest = Read-FeatureManifest -Path $lastApply.featureSource
            $manifestPath = $lastApply.featureSource
        }
    }

    # Build the plan: for every operation, capture the current state.
    $plan = @()
    foreach ($op in @($manifest.ops)) {
        switch ($op.type) {
            'registry.set' {
                $currentType = 'None'
                if (Test-Path -LiteralPath $op.path) {
                    try {
                        $currentType = [string](Get-Item -LiteralPath $op.path -ErrorAction Stop).GetValueKind($op.name)
                    }
                    catch {
                        $currentType = 'None'
                    }
                }
                $plan += [pscustomobject]@{
                    Op = 'registry.set'
                    Target = '{0}\{1}' -f $op.path, $op.name
                    Current = (Get-RegistryValueSafe -Path $op.path -Name $op.name)
                    CurrentType = $currentType
                    New = [string]$op.value
                    NewType = $op.valueType
                }
            }
            'service.startup' {
                $service = Get-Service -Name $op.name -ErrorAction SilentlyContinue
                $plan += [pscustomobject]@{
                    Op = 'service.startup'
                    Target = $op.name
                    Current = if ($service) { [string]$service.StartType } else { '<missing>' }
                    CurrentType = $null
                    New = $op.startupType
                    NewType = $null
                }
            }
            'registry.delete' {
                $currentType = 'None'
                if (Test-Path -LiteralPath $op.path) {
                    try {
                        $currentType = [string](Get-Item -LiteralPath $op.path -ErrorAction Stop).GetValueKind($op.name)
                    }
                    catch {
                        $currentType = 'None'
                    }
                }
                $plan += [pscustomobject]@{
                    Op = 'registry.delete'
                    Target = '{0}\{1}' -f $op.path, $op.name
                    Current = (Get-RegistryValueSafe -Path $op.path -Name $op.name)
                    CurrentType = $currentType
                    New = '<delete>'
                    NewType = $null
                }
            }
            'service.stop' {
                $service = Get-Service -Name $op.name -ErrorAction SilentlyContinue
                $plan += [pscustomobject]@{
                    Op = 'service.stop'
                    Target = $op.name
                    Current = if ($service) { [string]$service.Status } else { '<missing>' }
                    CurrentType = $null
                    New = 'Stopped'
                    NewType = $null
                }
            }
            'appx.remove' {
                $pkg = Get-AppxPackage -Name $op.name -ErrorAction SilentlyContinue
                $plan += [pscustomobject]@{
                    Op = 'appx.remove'
                    Target = $op.name
                    Current = if ($pkg) { $pkg.PackageFullName } else { '<missing>' }
                    CurrentType = $null
                    New = '<absent>'
                    NewType = $null
                }
            }
            'file.attribute' {
                # -Force: a file carrying the Hidden attribute is invisible
                # to Get-Item without it; Test-Path needs no switch here.
                $current = '<missing>'
                if (Test-Path -LiteralPath $op.path) {
                    $current = [string](Get-Item -LiteralPath $op.path -Force).Attributes
                }
                $plan += [pscustomobject]@{
                    Op = 'file.attribute'
                    Target = $op.path
                    Current = $current
                    CurrentType = $null
                    New = (@($op.attributes) -join ',')
                    NewType = $null
                }
            }
            'scheduler.task' {
                $task = Get-ScheduledTask -TaskPath $op.taskPath -TaskName $op.taskName -ErrorAction SilentlyContinue
                $plan += [pscustomobject]@{
                    Op = 'scheduler.task'
                    Target = '{0}{1}' -f $op.taskPath, $op.taskName
                    Current = if ($task) { [string]$task.State } else { '<missing>' }
                    CurrentType = $null
                    New = 'Disabled'
                    NewType = $null
                }
            }
            'network.dns' {
                $aliases = @(Get-DomovoyDnsTargets -InterfaceAlias $op.interfaceAlias)
                if ($aliases.Count -eq 0) { $aliases = @('<missing>') }
                foreach ($alias in $aliases) {
                    $dnsCurrent = $null
                    if ($alias -ne '<missing>') {
                        $dnsCurrent = Get-DnsClientServerAddress -InterfaceAlias $alias -AddressFamily IPv4 -ErrorAction SilentlyContinue
                    }
                    $plan += [pscustomobject]@{
                        Op = 'network.dns'
                        Target = $alias
                        Current = if ($dnsCurrent) { (@($dnsCurrent.ServerAddresses) -join ',') } else { '<missing>' }
                        CurrentType = $null
                        New = (@($op.servers) -join ',')
                        NewType = $null
                    }
                }
            }
            'network.proxy' {
                if ($op.mode -eq 'server' -and [string]::IsNullOrWhiteSpace([string]$op.proxyServer)) {
                    throw 'network.proxy: mode "server" requires the proxyServer field.'
                }
                if ($op.mode -eq 'pac' -and [string]::IsNullOrWhiteSpace([string]$op.autoConfigUrl)) {
                    throw 'network.proxy: mode "pac" requires the autoConfigUrl field.'
                }
                $proxyKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
                $curEnable = [string](Get-RegistryValueSafe -Path $proxyKey -Name 'ProxyEnable')
                $curServer = [string](Get-RegistryValueSafe -Path $proxyKey -Name 'ProxyServer')
                $curPac = [string](Get-RegistryValueSafe -Path $proxyKey -Name 'AutoConfigURL')
                $newState = switch ($op.mode) {
                    'off' { 'enable=0' }
                    'server' { 'enable=1;server={0}' -f $op.proxyServer }
                    'pac' { 'pac={0}' -f $op.autoConfigUrl }
                }
                $plan += [pscustomobject]@{
                    Op = 'network.proxy'
                    Target = 'WinINET (current user)'
                    Current = 'enable={0};server={1};pac={2}' -f $curEnable, $curServer, $curPac
                    CurrentType = $null
                    New = $newState
                    NewType = $null
                }
            }
            'file.timestamp' {
                # Catalog 91: set documented file timestamps; snapshot
                # and undo restore the exact previous stamps. Unpinned
                # stamps stay untouched - the plan says <keep> for them.
                $current = Get-DomovoyTimestampTriple -Path $op.path
                $currentText = 'creation={0};lastWrite={1};lastAccess={2}' -f $current['creation'], $current['lastWrite'], $current['lastAccess']
                $newParts = foreach ($field in @('creation', 'lastWrite', 'lastAccess')) {
                    $opProp = $op.PSObject.Properties[$field]
                    if ($opProp) {
                        # The manifest stores ISO 8601 strings (schema
                        # timestampValue), but ConvertFrom-Json hands the
                        # plan a DateTime - rendering it with the current
                        # culture printed "01/15/2024 10:30:00" and broke
                        # the documented plan contract (v1.4.1 fallout).
                        # The plan shows the instant in ISO 8601 again.
                        $stamp = $opProp.Value
                        if ($stamp -is [datetime]) {
                            if ($stamp.Kind -eq [System.DateTimeKind]::Local) {
                                $stamp = $stamp.ToUniversalTime()
                            }
                            $stamp = $stamp.ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)
                        }
                        '{0}={1}' -f $field, $stamp
                    }
                    else { '{0}=<keep>' -f $field }
                }
                $plan += [pscustomobject]@{
                    Op = 'file.timestamp'
                    Target = $op.path
                    Current = $currentText
                    CurrentType = $null
                    New = ($newParts -join ';')
                    NewType = $null
                }
            }
            'shell.handler.remove' {
                # Catalog 81: remove a documented context-menu handler
                # registration. Only the exact handler key is touched;
                # the Approved list and other handlers stay untouched.
                $keyPath = '{0}:\Software\Classes\{1}\shellex\ContextMenuHandlers\{2}' -f $op.hive, $op.class, $op.handler
                $current = '<missing>'
                if (Test-Path -LiteralPath $keyPath) {
                    try {
                        $defaultData = [string](Get-Item -LiteralPath $keyPath -ErrorAction Stop).GetValue('')
                        $current = if ($defaultData) { $defaultData } else { '<present>' }
                    }
                    catch {
                        $current = '<present>'
                    }
                }
                $plan += [pscustomobject]@{
                    Op = 'shell.handler.remove'
                    Target = $keyPath
                    Current = $current
                    CurrentType = $null
                    New = '<removed>'
                    NewType = $null
                }
            }
            'shell.handler.block' {
                # Catalog 81: add a CLSID to the documented Blocked list.
                # Nothing is deleted - the registration itself stays.
                $blockedKey = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked'
                $blockNew = if ($op.PSObject.Properties['reason']) { [string]$op.reason } else { '<blocked>' }
                $plan += [pscustomobject]@{
                    Op = 'shell.handler.block'
                    Target = [string]$op.clsid
                    Current = (Get-RegistryValueSafe -Path $blockedKey -Name $op.clsid)
                    CurrentType = $null
                    New = $blockNew
                    NewType = $null
                }
            }
            'shell.openwith.remove' {
                # Catalog 81: remove an "Open with" suggestion for one
                # extension (per-user FileExts associations).
                $owKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\{0}\{1}' -f $op.extension, $op.kind
                $owCurrent = '<absent>'
                if (Test-Path -LiteralPath $owKey) {
                    try {
                        $owItem = Get-Item -LiteralPath $owKey -ErrorAction Stop
                        if ($op.kind -eq 'OpenWithList') {
                            foreach ($valueName in @($owItem.GetValueNames())) {
                                if ($valueName -ieq 'MRUList') { continue }
                                $data = [string]$owItem.GetValue($valueName)
                                if ($data -ieq [string]$op.entry) {
                                    $owCurrent = '{0}={1}' -f $valueName, $data
                                    break
                                }
                            }
                        }
                        else {
                            if ($null -ne $owItem.GetValue([string]$op.entry)) {
                                $owCurrent = '<present>'
                            }
                        }
                    }
                    catch {
                        $owCurrent = '<absent>'
                    }
                }
                $plan += [pscustomobject]@{
                    Op = 'shell.openwith.remove'
                    Target = '{0}|{1}|{2}' -f $op.extension, $op.kind, $op.entry
                    Current = $owCurrent
                    CurrentType = $null
                    New = '<removed>'
                    NewType = $null
                }
            }
            default {
                throw "Unsupported op type: $($op.type)"
            }
        }
    }

    # Dry-run by default (invariant I3).
    if (-not $Apply) {
        [pscustomobject]@{
            Feature = $manifest.id
            Mode = 'DryRun'
            Plan = $plan
        }
        return
    }

    # Elevation is checked explicitly (invariant I5).
    if (-not (Test-DomovoyAdmin)) {
        throw 'Applying features requires an elevated PowerShell session.'
    }

    if ($PSCmdlet.ShouldProcess($manifest.id, 'Apply feature operations')) {
        # System restore point (soft: Windows allows one per 24h).
        if (-not $SkipRestorePoint) {
            try {
                New-DomovoyRestorePoint -Description "Domovoy: $($manifest.id)" -ErrorAction Stop | Out-Null
            }
            catch {
                Write-Verbose ("Restore point was not created: {0}" -f $_.Exception.Message)
            }
        }

        # Snapshot before the first operation (invariant I2).
        $snapshot = @()
        foreach ($op in @($manifest.ops)) {
            switch ($op.type) {
                'registry.set' {
                    $kind = 'None'
                    if (Test-Path -LiteralPath $op.path) {
                        try {
                            $kind = [string](Get-Item -LiteralPath $op.path -ErrorAction Stop).GetValueKind($op.name)
                        }
                        catch {
                            $kind = 'None'
                        }
                    }
                    $snapshot += @{
                        op = 'registry.set'
                        path = $op.path
                        name = $op.name
                        previousValue = (Get-RegistryValueSafe -Path $op.path -Name $op.name)
                        previousType = $kind
                        pathExisted = [bool](Test-Path -LiteralPath $op.path)
                    }
                }
                'service.startup' {
                    $service = Get-Service -Name $op.name -ErrorAction SilentlyContinue
                    $snapshot += @{
                        op = 'service.startup'
                        name = $op.name
                        previousValue = if ($service) { [string]$service.StartType } else { '<missing>' }
                    }
                }
                'registry.delete' {
                    $kind = 'None'
                    if (Test-Path -LiteralPath $op.path) {
                        try {
                            $kind = [string](Get-Item -LiteralPath $op.path -ErrorAction Stop).GetValueKind($op.name)
                        }
                        catch {
                            $kind = 'None'
                        }
                    }
                    $snapshot += @{
                        op = 'registry.delete'
                        path = $op.path
                        name = $op.name
                        previousValue = (Get-RegistryValueSafe -Path $op.path -Name $op.name)
                        previousType = $kind
                    }
                }
                'service.stop' {
                    $service = Get-Service -Name $op.name -ErrorAction SilentlyContinue
                    $snapshot += @{
                        op = 'service.stop'
                        name = $op.name
                        previousStatus = if ($service) { [string]$service.Status } else { '<missing>' }
                    }
                }
                'appx.remove' {
                    $pkg = Get-AppxPackage -Name $op.name -ErrorAction SilentlyContinue
                    $provName = '<missing>'
                    if ($op.removeProvisioned) {
                        $prov = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
                            Where-Object { $_.DisplayName -eq $op.name } |
                            Select-Object -First 1
                        if ($prov) { $provName = $prov.PackageName }
                    }
                    $snapshot += @{
                        op = 'appx.remove'
                        name = $op.name
                        packageFullName = if ($pkg) { $pkg.PackageFullName } else { '<missing>' }
                        installLocation = if ($pkg) { $pkg.InstallLocation } else { '<missing>' }
                        provisionedPackageName = $provName
                    }
                }
                'file.attribute' {
                    # -Force: the target file may already carry the Hidden attribute.
                    $previousAttributes = '<missing>'
                    if (Test-Path -LiteralPath $op.path) {
                        $previousAttributes = [string](Get-Item -LiteralPath $op.path -Force).Attributes
                    }
                    $snapshot += @{
                        op = 'file.attribute'
                        path = $op.path
                        previousAttributes = $previousAttributes
                    }
                }
                'scheduler.task' {
                    $task = Get-ScheduledTask -TaskPath $op.taskPath -TaskName $op.taskName -ErrorAction SilentlyContinue
                    $snapshot += @{
                        op = 'scheduler.task'
                        taskPath = $op.taskPath
                        taskName = $op.taskName
                        previousState = if ($task) { [string]$task.State } else { '<missing>' }
                    }
                }
                'network.dns' {
                    foreach ($alias in @(Get-DomovoyDnsTargets -InterfaceAlias $op.interfaceAlias)) {
                        $dnsCurrent = Get-DnsClientServerAddress -InterfaceAlias $alias -AddressFamily IPv4 -ErrorAction SilentlyContinue
                        $snapshot += @{
                            op = 'network.dns'
                            interfaceAlias = $alias
                            previousServers = @($dnsCurrent.ServerAddresses)
                        }
                    }
                }
                'network.proxy' {
                    $proxyKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
                    $snapshot += @{
                        op = 'network.proxy'
                        target = 'WinINET (current user)'
                        previousProxyEnable = (Get-RegistryValueSafe -Path $proxyKey -Name 'ProxyEnable')
                        previousProxyServer = (Get-RegistryValueSafe -Path $proxyKey -Name 'ProxyServer')
                        previousAutoConfigUrl = (Get-RegistryValueSafe -Path $proxyKey -Name 'AutoConfigURL')
                        previousProxyOverride = (Get-RegistryValueSafe -Path $proxyKey -Name 'ProxyOverride')
                    }
                }
                'file.timestamp' {
                    $previous = Get-DomovoyTimestampTriple -Path $op.path
                    $snapshot += @{
                        op = 'file.timestamp'
                        path = $op.path
                        previousCreation = $previous['creation']
                        previousLastWrite = $previous['lastWrite']
                        previousLastAccess = $previous['lastAccess']
                    }
                }
                'shell.handler.remove' {
                    $keyPath = '{0}:\Software\Classes\{1}\shellex\ContextMenuHandlers\{2}' -f $op.hive, $op.class, $op.handler
                    $tree = Get-DomovoyRegKeyTree -Path $keyPath
                    $snapshot += @{
                        op = 'shell.handler.remove'
                        key = $keyPath
                        keyExisted = ($null -ne $tree)
                        tree = $tree
                    }
                }
                'shell.handler.block' {
                    $blockedKey = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked'
                    $snapshot += @{
                        op = 'shell.handler.block'
                        clsid = [string]$op.clsid
                        previousValue = (Get-RegistryValueSafe -Path $blockedKey -Name $op.clsid)
                    }
                }
                'shell.openwith.remove' {
                    $owKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\{0}\{1}' -f $op.extension, $op.kind
                    if ($op.kind -eq 'OpenWithList') {
                        $removedLetters = @()
                        $mruExisted = $false
                        $mruData = ''
                        try {
                            $listItem = Get-Item -LiteralPath $owKey -ErrorAction Stop
                            foreach ($valueName in @($listItem.GetValueNames())) {
                                if ($valueName -ieq 'MRUList') {
                                    $mruExisted = $true
                                    $mruData = [string]$listItem.GetValue($valueName)
                                    continue
                                }
                                if ([string]$listItem.GetValue($valueName) -ieq [string]$op.entry) {
                                    $removedLetters += @{
                                        letter = [string]$valueName
                                        data = [string]$listItem.GetValue($valueName)
                                    }
                                }
                            }
                        }
                        catch {
                            # No OpenWithList key for this extension: nothing to remove.
                        }
                        $snapshot += @{
                            op = 'shell.openwith.remove'
                            extension = [string]$op.extension
                            kind = 'OpenWithList'
                            entry = [string]$op.entry
                            valueExisted = (@($removedLetters).Count -gt 0)
                            removedLetters = @($removedLetters)
                            mruExisted = $mruExisted
                            previousMrulist = $mruData
                        }
                    }
                    else {
                        $existed = $false
                        $prevData = $null
                        $prevKind = 'String'
                        try {
                            $progItem = Get-Item -LiteralPath $owKey -ErrorAction Stop
                            $raw = $progItem.GetValue([string]$op.entry)
                            if ($null -ne $raw) {
                                $existed = $true
                                $prevData = $raw
                                $prevKind = [string]$progItem.GetValueKind([string]$op.entry)
                            }
                        }
                        catch {
                            # No OpenWithProgids key for this extension.
                        }
                        if ($existed -and $prevKind -eq 'Binary' -and $null -ne $prevData) {
                            $prevData = [Convert]::ToBase64String([byte[]]$prevData)
                        }
                        $snapshot += @{
                            op = 'shell.openwith.remove'
                            extension = [string]$op.extension
                            kind = 'OpenWithProgids'
                            entry = [string]$op.entry
                            valueExisted = $existed
                            previousData = $prevData
                            previousKind = $prevKind
                        }
                    }
                }
            }
        }

        # Execute operations.
        foreach ($op in @($manifest.ops)) {
            switch ($op.type) {
                'registry.set' {
                    if (-not (Test-Path -LiteralPath $op.path)) {
                        $null = New-Item -Path $op.path -ItemType Directory -Force
                    }
                    $null = New-ItemProperty -LiteralPath $op.path -Name $op.name -Value $op.value -PropertyType $op.valueType -Force
                }
                'service.startup' {
                    Set-Service -Name $op.name -StartupType $op.startupType
                }
                'registry.delete' {
                    Remove-ItemProperty -LiteralPath $op.path -Name $op.name -ErrorAction SilentlyContinue
                }
                'service.stop' {
                    $running = Get-Service -Name $op.name -ErrorAction SilentlyContinue
                    if ($running -and $running.Status -eq 'Running') {
                        Stop-Service -Name $op.name -Force -ErrorAction Stop
                    }
                }
                'appx.remove' {
                    $pkg = Get-AppxPackage -Name $op.name -ErrorAction SilentlyContinue
                    if ($pkg) {
                        Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction Stop
                    }
                    if ($op.removeProvisioned) {
                        $provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop |
                            Where-Object { $_.DisplayName -eq $op.name })
                        foreach ($provisionedItem in $provisioned) {
                            $null = Remove-AppxProvisionedPackage -Online -PackageName $provisionedItem.PackageName -ErrorAction Stop
                        }
                    }
                }
                'file.attribute' {
                    if (-not (Test-Path -LiteralPath $op.path)) {
                        if (-not $op.allowMissing) {
                            throw ("Path not found for file.attribute: {0}" -f $op.path)
                        }
                    }
                    else {
                        $item = Get-Item -LiteralPath $op.path -Force
                        $newAttributes = $item.Attributes
                        foreach ($attrName in @($op.attributes)) {
                            $newAttributes = $newAttributes -bor [System.IO.FileAttributes]::$attrName
                        }
                        $item.Attributes = $newAttributes
                    }
                }
                'scheduler.task' {
                    $task = Get-ScheduledTask -TaskPath $op.taskPath -TaskName $op.taskName -ErrorAction SilentlyContinue
                    if ($task -and $task.State -ne 'Disabled') {
                        $null = Disable-ScheduledTask -TaskPath $op.taskPath -TaskName $op.taskName -ErrorAction Stop
                    }
                }
                'network.dns' {
                    foreach ($alias in @(Get-DomovoyDnsTargets -InterfaceAlias $op.interfaceAlias)) {
                        $null = Set-DnsClientServerAddress -InterfaceAlias $alias -ServerAddresses @($op.servers) -ErrorAction Stop
                    }
                }
                'network.proxy' {
                    $proxyKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
                    if (-not (Test-Path -LiteralPath $proxyKey)) {
                        $null = New-Item -Path $proxyKey -ItemType Directory -Force
                    }
                    switch ($op.mode) {
                        'off' {
                            $null = New-ItemProperty -LiteralPath $proxyKey -Name 'ProxyEnable' -Value 0 -PropertyType DWord -Force
                        }
                        'server' {
                            $null = New-ItemProperty -LiteralPath $proxyKey -Name 'ProxyEnable' -Value 1 -PropertyType DWord -Force
                            $null = New-ItemProperty -LiteralPath $proxyKey -Name 'ProxyServer' -Value ([string]$op.proxyServer) -PropertyType String -Force
                            if ($op.PSObject.Properties['bypassLocal'] -and $op.bypassLocal) {
                                $null = New-ItemProperty -LiteralPath $proxyKey -Name 'ProxyOverride' -Value '<local>' -PropertyType String -Force
                            }
                        }
                        'pac' {
                            $null = New-ItemProperty -LiteralPath $proxyKey -Name 'AutoConfigURL' -Value ([string]$op.autoConfigUrl) -PropertyType String -Force
                        }
                    }
                }
                'file.timestamp' {
                    if (-not (Test-Path -LiteralPath $op.path)) {
                        if (-not ($op.PSObject.Properties['allowMissing'] -and $op.allowMissing)) {
                            throw ("Path not found for file.timestamp: {0}" -f $op.path)
                        }
                    }
                    else {
                        foreach ($field in @('creation', 'lastWrite', 'lastAccess')) {
                            $opProp = $op.PSObject.Properties[$field]
                            if ($opProp) {
                                Set-DomovoyTimestamp -Path $op.path -Field $field -Value ([string]$opProp.Value)
                            }
                        }
                    }
                }
                'shell.handler.remove' {
                    $keyPath = '{0}:\Software\Classes\{1}\shellex\ContextMenuHandlers\{2}' -f $op.hive, $op.class, $op.handler
                    if (Test-Path -LiteralPath $keyPath) {
                        Remove-Item -LiteralPath $keyPath -Recurse -Force
                    }
                }
                'shell.handler.block' {
                    $blockedKey = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked'
                    if (-not (Test-Path -LiteralPath $blockedKey)) {
                        $null = New-Item -Path $blockedKey -ItemType Directory -Force
                    }
                    # Idempotent (I6): an existing Blocked entry is never
                    # clobbered - the op adds the block, not rewrites it.
                    $existing = Get-RegistryValueSafe -Path $blockedKey -Name $op.clsid
                    if ($existing -eq '<unset>') {
                        $blockData = if ($op.PSObject.Properties['reason']) { [string]$op.reason } else { '' }
                        $null = New-ItemProperty -LiteralPath $blockedKey -Name $op.clsid -Value $blockData -PropertyType String -Force
                    }
                }
                'shell.openwith.remove' {
                    $owKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\{0}\{1}' -f $op.extension, $op.kind
                    if ($op.kind -eq 'OpenWithList') {
                        $letters = @()
                        try {
                            $listItem = Get-Item -LiteralPath $owKey -ErrorAction Stop
                            foreach ($valueName in @($listItem.GetValueNames())) {
                                if ($valueName -ieq 'MRUList') { continue }
                                if ([string]$listItem.GetValue($valueName) -ieq [string]$op.entry) {
                                    $letters += $valueName
                                }
                            }
                        }
                        catch {
                            $letters = @()
                        }
                        foreach ($letter in $letters) {
                            Remove-ItemProperty -LiteralPath $owKey -Name $letter -ErrorAction SilentlyContinue
                        }
                        if ($letters.Count -gt 0) {
                            $mru = [string]$listItem.GetValue('MRUList')
                            foreach ($letter in $letters) {
                                $mru = $mru.Replace($letter, '')
                            }
                            if ($mru -eq '') {
                                Remove-ItemProperty -LiteralPath $owKey -Name 'MRUList' -ErrorAction SilentlyContinue
                            }
                            else {
                                $null = New-ItemProperty -LiteralPath $owKey -Name 'MRUList' -Value $mru -PropertyType String -Force
                            }
                        }
                    }
                    else {
                        Remove-ItemProperty -LiteralPath $owKey -Name ([string]$op.entry) -ErrorAction SilentlyContinue
                    }
                }
            }
        }

        # Verify, diff against the snapshot and record.
        $verification = Test-DomovoyEffect -Manifest $manifest
        $changes = Get-DomovoyChangeSet -Manifest $manifest -Snapshot $snapshot -Verification $verification
        $written = Write-DomovoyLedgerEntry -Entry @{
            event = 'feature.apply'
            featureId = $manifest.id
            featureVersion = $manifest.version
            featureSource = $manifestPath
            snapshot = $snapshot
            verification = $verification
        }

        [pscustomobject]@{
            Feature = $manifest.id
            Mode = 'Apply'
            Verification = $verification
            Changes = $changes
            LedgerTimestamp = $written['timestamp']
        }
    }
}
