function Get-DomovoyShellMenuReport {
    <#
    .SYNOPSIS
    Audits context-menu shell extensions and the "Open with" associations.
    Read-only (catalog 104, the groundwork of catalog 81).

    .DESCRIPTION
    Answers two questions honestly, without changing anything:

    1. Who hangs on the context menu? Every documented shell extension
       registration point (the ContextMenuHandlers keys under *, All-
       FilesystemObjects, Directory, Directory\Background, Folder and
       Drive) is listed with its CLSID, resolved COM server (InprocServer32)
       and three honest verdicts: is the server DLL present on disk, is the
       CLSID present in the documented "Approved" list, and does the handler
       carry a CLSID at all.

    2. What does "Open with" offer for a file extension? The per-user
       FileExts associations (OpenWithList programs and OpenWithProgids
       PROGIDs) are inventoried - for every extension, or for the one
       requested with -Extension.

    Everything is read from documented registry locations with the built-in
    provider: no external process, no network (invariant I4). A missing key
    is an empty answer, not an error.

    .PARAMETER Extension
    Restrict the "Open with" section to one extension (for example '.txt';
    the leading dot is added when missing). The context-menu section is
    always reported in full.

    .EXAMPLE
    Get-DomovoyShellMenuReport

    .EXAMPLE
    Get-DomovoyShellMenuReport -Extension .txt
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string]$Extension
    )

    if (($PSVersionTable.PSVersion.Major -ge 6) -and -not $IsWindows) {
        throw 'Get-DomovoyShellMenuReport reads the Windows registry: it requires Windows.'
    }

    # Documented context-menu registration points (HKCR is the merged view
    # of HKLM\Software\Classes and HKCU\Software\Classes). The literal '*'
    # in the first path is why every lookup below goes through -LiteralPath.
    $handlerRoots = @(
        @{ Name = '*';                     Key = 'Registry::HKEY_CLASSES_ROOT\*\shellex\ContextMenuHandlers' },
        @{ Name = 'AllFilesystemObjects';  Key = 'Registry::HKEY_CLASSES_ROOT\AllFilesystemObjects\shellex\ContextMenuHandlers' },
        @{ Name = 'Directory';             Key = 'Registry::HKEY_CLASSES_ROOT\Directory\shellex\ContextMenuHandlers' },
        @{ Name = 'Directory\Background';  Key = 'Registry::HKEY_CLASSES_ROOT\Directory\Background\shellex\ContextMenuHandlers' },
        @{ Name = 'Folder';                Key = 'Registry::HKEY_CLASSES_ROOT\Folder\shellex\ContextMenuHandlers' },
        @{ Name = 'Drive';                 Key = 'Registry::HKEY_CLASSES_ROOT\Drive\shellex\ContextMenuHandlers' }
    )
    $approvedKey = 'Registry::HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\Shell Extensions\Approved'
    $clsidRoot = 'Registry::HKEY_CLASSES_ROOT\CLSID'
    $fileExtsKey = 'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts'

    $locationsScanned = 0
    $locationsPresent = 0
    $handlers = @()

    foreach ($root in $handlerRoots) {
        $locationsScanned++
        $children = $null
        try {
            $children = @(Get-ChildItem -LiteralPath $root.Key -ErrorAction Stop)
        }
        catch {
            # A registration point that does not exist on this machine is an
            # empty answer, not an error.
            $children = @()
        }
        if ($children.Count -gt 0) { $locationsPresent++ }

        foreach ($child in $children) {
            $handlerName = $child.PSChildName
            $clsid = ''
            try {
                $clsid = [string](Get-Item -LiteralPath $child.PSPath -ErrorAction Stop).GetValue('')
            }
            catch {
                $clsid = ''
            }

            $server = ''
            $dllPresent = $null
            $approved = $false

            if ([string]::IsNullOrWhiteSpace($clsid)) {
                # A handler key without a CLSID cannot be resolved further;
                # the row still appears - honesty beats silence.
                $handlers += [pscustomobject]@{
                    Location   = $root.Name
                    Handler    = $handlerName
                    Clsid      = ''
                    Server     = ''
                    DllPresent = $null
                    Approved   = $false
                }
                continue
            }

            $clsidKey = Join-Path -Path $clsidRoot -ChildPath $clsid
            try {
                $inproc = Get-Item -LiteralPath (Join-Path -Path $clsidKey -ChildPath 'InprocServer32') -ErrorAction Stop
                $server = [string]$inproc.GetValue('')
            }
            catch {
                $server = ''
            }

            if (-not [string]::IsNullOrWhiteSpace($server)) {
                $dllPath = [Environment]::ExpandEnvironmentVariables($server).Trim('"').Trim()
                $dllPresent = (Test-Path -LiteralPath $dllPath -ErrorAction SilentlyContinue)
            }

            try {
                $approvedItem = Get-Item -LiteralPath $approvedKey -ErrorAction Stop
                $approvedValue = $approvedItem.GetValue($clsid)
                $approved = ($null -ne $approvedValue)
            }
            catch {
                $approved = $false
            }

            $handlers += [pscustomobject]@{
                Location   = $root.Name
                Handler    = $handlerName
                Clsid      = $clsid
                Server     = $server
                DllPresent = $dllPresent
                Approved   = $approved
            }
        }
    }

    # "Open with": per-user FileExts associations.
    $openWithRows = @()
    $extensionsScanned = 0
    $extensionFilter = $null
    if (-not [string]::IsNullOrWhiteSpace($Extension)) {
        $extensionFilter = if ($Extension.StartsWith('.')) { $Extension.ToLowerInvariant() } else { '.' + $Extension.ToLowerInvariant() }
    }

    $extKeys = @()
    try {
        $extKeys = @(Get-ChildItem -LiteralPath $fileExtsKey -ErrorAction Stop)
    }
    catch {
        $extKeys = @()
    }

    foreach ($extKey in $extKeys) {
        $extensionsScanned++
        $extName = $extKey.PSChildName.ToLowerInvariant()
        if ($extensionFilter -and $extName -ne $extensionFilter) { continue }

        $programs = @()
        $progIds = @()
        $mruList = ''

        $listKey = Join-Path -Path $extKey.PSPath -ChildPath 'OpenWithList'
        try {
            $list = Get-Item -LiteralPath $listKey -ErrorAction Stop
            $mruList = [string]$list.GetValue('MRUList')
            foreach ($value in $list.GetValueNames()) {
                if ($value -ieq 'MRUList') { continue }
                $programs += [string]$list.GetValue($value)
            }
        }
        catch {
            # No OpenWithList for this extension.
        }

        $progIdKey = Join-Path -Path $extKey.PSPath -ChildPath 'OpenWithProgids'
        try {
            $progIdItem = Get-Item -LiteralPath $progIdKey -ErrorAction Stop
            foreach ($value in $progIdItem.GetValueNames()) {
                $progIds += [string]$value
            }
        }
        catch {
            # No OpenWithProgids for this extension.
        }

        if ($programs.Count -eq 0 -and $progIds.Count -eq 0 -and -not $extensionFilter) {
            # Nothing to report for this extension - it is still counted in
            # the scanned total above.
            continue
        }

        $openWithRows += [pscustomobject]@{
            Extension    = $extName
            Programs     = @($programs)
            ProgIds      = @($progIds)
            Mrulist      = $mruList
            Choices      = (@($programs).Count + @($progIds).Count)
        }
    }

    $missingDll = @($handlers | Where-Object { $null -ne $_.DllPresent -and -not $_.DllPresent }).Count
    $noClsid = @($handlers | Where-Object { [string]::IsNullOrWhiteSpace($_.Clsid) }).Count
    $unapproved = @($handlers | Where-Object { -not $_.Approved }).Count
    $choicesTotal = 0
    foreach ($row in $openWithRows) { $choicesTotal += $row.Choices }

    [pscustomobject]@{
        LocationsScanned          = $locationsScanned
        LocationsPresent          = $locationsPresent
        ContextMenuHandlers       = $handlers
        OpenWithExtensions        = $openWithRows
        OpenWithExtensionsScanned = $extensionsScanned
        Summary                   = [pscustomobject]@{
            HandlersTotal     = @($handlers).Count
            HandlersMissingDll = $missingDll
            HandlersNoClsid   = $noClsid
            HandlersUnapproved = $unapproved
            OpenWithExtensionCount = @($openWithRows).Count
            OpenWithChoicesTotal   = $choicesTotal
        }
    }
}
