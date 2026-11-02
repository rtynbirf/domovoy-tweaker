# Domovoy v1.4.0 tests: the shell operation set (catalog 81) on top of the
# read-only audit from v1.3 (catalog 104) - context-menu handler removal with
# the byte-exact tree undo, "Open with" entry removal with the exact
# MRUList/letter restore, and the Blocked-list operation. Everything runs on
# synthetic per-user keys created for the test and cleaned up afterwards;
# the HKLM Blocked list is only touched with a synthetic CLSID whose
# previous state is restored - the registration itself is never touched.

# NOTE: the variable must not be named *isWindows* - that name collides
# with the read-only automatic $IsWindows (names are case-insensitive).
# Pester 5 evaluates -Skip during DISCOVERY, before BeforeAll runs - the
# flag must be a file-level assignment, or every platform gate reads an
# undefined variable and silently loses its meaning.
$script:isWindowsPlatform = ($PSVersionTable.PSVersion.Major -lt 6) -or $IsWindows

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $env:DOMOVOY_STORE = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("domovoy-v14-shell-" + [guid]::NewGuid().ToString('N'))
    $env:DOMOVOY_FEATURES_DIR = Join-Path -Path $repoRoot -ChildPath 'config/features'
    Import-Module (Join-Path -Path $repoRoot -ChildPath 'src/Domovoy/Domovoy.psd1') -Force

    $script:v14RepoRoot = $repoRoot
    $script:v14ManifestDir = Join-Path -Path $env:DOMOVOY_STORE -ChildPath 'manifests'
    New-Item -Path $script:v14ManifestDir -ItemType Directory -Force | Out-Null

    function New-V14ShellManifest {
        param(
            [string]$Id,
            [object[]]$Ops,
            [object[]]$Verify
        )
        $path = Join-Path -Path $script:v14ManifestDir -ChildPath ($Id + '.json')
        @{
            id = $Id
            title = "Test fixture: $Id"
            version = '1.0.0'
            category = 'core'
            risk = 'medium'
            description = "Test fixture for the v1.4 shell operation set: synthetic per-user registrations only; $Id."
            ops = $Ops
            undo = @{ mode = 'snapshot' }
            verify = $Verify
            references = @('https://learn.microsoft.com/windows/win32/shell/context-menu-handlers')
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
        return $path
    }

    # Synthetic, fully documented registrations under HKCU.
    $script:v14Class = '.domovoyv14e2e'
    $script:v14Handler = 'DvmE2EHandler'
    $script:v14Clsid = '{' + [guid]::NewGuid().ToString().ToUpperInvariant() + '}'
    $script:v14Ext = '.domovoyv14e2e'

    $handlerKey = 'Registry::HKEY_CURRENT_USER\Software\Classes\{0}\shellex\ContextMenuHandlers\{1}' -f $script:v14Class, $script:v14Handler
    $null = New-Item -Path $handlerKey -Force
    $null = Set-Item -LiteralPath $handlerKey -Value $script:v14Clsid

    $extKey = 'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\{0}' -f $script:v14Ext
    $null = New-Item -Path (Join-Path -Path $extKey -ChildPath 'OpenWithList') -Force
    $null = New-ItemProperty -LiteralPath (Join-Path -Path $extKey -ChildPath 'OpenWithList') -Name 'a' -Value 'dvmappA.exe' -PropertyType String -Force
    $null = New-ItemProperty -LiteralPath (Join-Path -Path $extKey -ChildPath 'OpenWithList') -Name 'b' -Value 'dvmappB.exe' -PropertyType String -Force
    $null = New-ItemProperty -LiteralPath (Join-Path -Path $extKey -ChildPath 'OpenWithList') -Name 'MRUList' -Value 'ba' -PropertyType String -Force
    $null = New-Item -Path (Join-Path -Path $extKey -ChildPath 'OpenWithProgids') -Force
    $null = New-ItemProperty -LiteralPath (Join-Path -Path $extKey -ChildPath 'OpenWithProgids') -Name 'DvmE2E.progid' -Value 'DvmE2E backup choice' -PropertyType String -Force
}

AfterAll {
    Remove-Module -Name Domovoy -Force -ErrorAction SilentlyContinue
    # The synthetic registrations never outlive the suite, whatever the
    # ledger said - the store and the keys are per-run fixtures.
    Remove-Item -LiteralPath (Join-Path -Path 'Registry::HKEY_CURRENT_USER\Software\Classes' -ChildPath $script:v14Class) -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path -Path 'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts' -ChildPath $script:v14Ext) -Recurse -Force -ErrorAction SilentlyContinue
    Remove-ItemProperty -LiteralPath 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked' -Name $script:v14Clsid -ErrorAction SilentlyContinue
    if ($env:DOMOVOY_STORE -like "$([System.IO.Path]::GetTempPath())domovoy-v14-shell-*") {
        Remove-Item -LiteralPath $env:DOMOVOY_STORE -Recurse -Force -ErrorAction SilentlyContinue
    }
}


Describe 'Shell handler removal (catalog 81)' -Skip:(-not $script:isWindowsPlatform) {

    It 'apply removes exactly the named handler; undo restores the exact registration' {
        $handlerKey = 'Registry::HKEY_CURRENT_USER\Software\Classes\{0}\shellex\ContextMenuHandlers\{1}' -f $script:v14Class, $script:v14Handler
        (Test-Path -LiteralPath $handlerKey) | Should -BeTrue

        $manifest = New-V14ShellManifest -Id 'e2e.shell.handler.remove' `
            -Ops @(@{ type = 'shell.handler.remove'; hive = 'HKCU'; class = $script:v14Class; handler = $script:v14Handler }) `
            -Verify @(@{ type = 'shell.handler.absent'; hive = 'HKCU'; class = $script:v14Class; handler = $script:v14Handler })

        $applied = Invoke-DomovoyFeature -ManifestFile $manifest -Apply -SkipRestorePoint
        $applied.Mode | Should -Be 'Apply'
        $applied.Verification.AllPass | Should -BeTrue
        (Test-Path -LiteralPath $handlerKey) | Should -BeFalse

        $undo = Undo-DomovoyFeature -Id 'e2e.shell.handler.remove' -Apply
        $undo.Mode | Should -Be 'Undo'
        (Test-Path -LiteralPath $handlerKey) | Should -BeTrue
        (Get-Item -LiteralPath $handlerKey).GetValue('') | Should -Be $script:v14Clsid
    }

    It 'apply on an absent handler is honest; undo restores the absence' {
        $ghostHandler = 'DvmGhostHandler'
        $ghostKey = 'Registry::HKEY_CURRENT_USER\Software\Classes\{0}\shellex\ContextMenuHandlers\{1}' -f $script:v14Class, $ghostHandler
        (Test-Path -LiteralPath $ghostKey) | Should -BeFalse

        $manifest = New-V14ShellManifest -Id 'e2e.shell.handler.absent' `
            -Ops @(@{ type = 'shell.handler.remove'; hive = 'HKCU'; class = $script:v14Class; handler = $ghostHandler }) `
            -Verify @(@{ type = 'shell.handler.absent'; hive = 'HKCU'; class = $script:v14Class; handler = $ghostHandler })

        $applied = Invoke-DomovoyFeature -ManifestFile $manifest -Apply -SkipRestorePoint
        $applied.Mode | Should -Be 'Apply'
        $applied.Verification.AllPass | Should -BeTrue

        $undo = Undo-DomovoyFeature -Id 'e2e.shell.handler.absent' -Apply
        $undo.Mode | Should -Be 'Undo'
        (Test-Path -LiteralPath $ghostKey) | Should -BeFalse
    }

    It 'the Approved CLSID list is never touched by a handler removal' {
        $approvedKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Shell Extensions\Approved'
        $approvedExisted = Test-Path -LiteralPath $approvedKey
        $before = if ($approvedExisted) { @(Get-Item -LiteralPath $approvedKey).Property } else { @() }

        $manifest = New-V14ShellManifest -Id 'e2e.shell.handler.approved' `
            -Ops @(@{ type = 'shell.handler.remove'; hive = 'HKCU'; class = $script:v14Class; handler = $script:v14Handler }) `
            -Verify @(@{ type = 'shell.handler.absent'; hive = 'HKCU'; class = $script:v14Class; handler = $script:v14Handler })
        $null = Invoke-DomovoyFeature -ManifestFile $manifest -Apply -SkipRestorePoint
        $null = Undo-DomovoyFeature -Id 'e2e.shell.handler.approved' -Apply

        if ($approvedExisted) {
            @(Get-Item -LiteralPath $approvedKey).Property | Should -Be $before
        }
        else {
            Test-Path -LiteralPath $approvedKey | Should -BeFalse
        }
    }
}

Describe 'Open-with entry removal (catalog 81)' -Skip:(-not $script:isWindowsPlatform) {

    It 'apply drops the letter and rebalances MRUList; undo restores letters and the exact MRUList' {
        $listKey = 'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\{0}\OpenWithList' -f $script:v14Ext
        (Get-Item -LiteralPath $listKey).GetValue('MRUList') | Should -Be 'ba'

        $manifest = New-V14ShellManifest -Id 'e2e.openwith.list.remove' `
            -Ops @(@{ type = 'shell.openwith.remove'; extension = $script:v14Ext; kind = 'OpenWithList'; entry = 'dvmappA.exe' }) `
            -Verify @(@{ type = 'shell.openwith.absent'; extension = $script:v14Ext; kind = 'OpenWithList'; entry = 'dvmappA.exe' })

        $applied = Invoke-DomovoyFeature -ManifestFile $manifest -Apply -SkipRestorePoint
        $applied.Mode | Should -Be 'Apply'
        $applied.Verification.AllPass | Should -BeTrue
        $after = Get-Item -LiteralPath $listKey
        @($after.GetValueNames() | Where-Object { $_ -ne 'MRUList' }) | Should -Be 'b'
        $after.GetValue('MRUList') | Should -Be 'b'

        $undo = Undo-DomovoyFeature -Id 'e2e.openwith.list.remove' -Apply
        $undo.Mode | Should -Be 'Undo'
        $restored = Get-Item -LiteralPath $listKey
        $restored.GetValue('a') | Should -Be 'dvmappA.exe'
        $restored.GetValue('b') | Should -Be 'dvmappB.exe'
        $restored.GetValue('MRUList') | Should -Be 'ba'
    }

    It 'apply on OpenWithProgids removes the exact value; undo restores the exact data' {
        $progIdsKey = 'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\{0}\OpenWithProgids' -f $script:v14Ext
        (Get-Item -LiteralPath $progIdsKey).GetValue('DvmE2E.progid') | Should -Be 'DvmE2E backup choice'

        $manifest = New-V14ShellManifest -Id 'e2e.openwith.progids.remove' `
            -Ops @(@{ type = 'shell.openwith.remove'; extension = $script:v14Ext; kind = 'OpenWithProgids'; entry = 'DvmE2E.progid' }) `
            -Verify @(@{ type = 'shell.openwith.absent'; extension = $script:v14Ext; kind = 'OpenWithProgids'; entry = 'DvmE2E.progid' })

        $applied = Invoke-DomovoyFeature -ManifestFile $manifest -Apply -SkipRestorePoint
        $applied.Mode | Should -Be 'Apply'
        $applied.Verification.AllPass | Should -BeTrue
        (Get-Item -LiteralPath $progIdsKey).GetValue('DvmE2E.progid') | Should -BeNullOrEmpty

        $undo = Undo-DomovoyFeature -Id 'e2e.openwith.progids.remove' -Apply
        $undo.Mode | Should -Be 'Undo'
        $restored = Get-Item -LiteralPath $progIdsKey
        $restored.GetValue('DvmE2E.progid') | Should -Be 'DvmE2E backup choice'
        $restored.GetValueKind('DvmE2E.progid') | Should -Be 'String'
    }
}

Describe 'Shell extension block op (catalog 81)' -Skip:(-not $script:isWindowsPlatform) {

    It 'apply blocks the synthetic CLSID; undo restores the previous state' -Skip:(-not ($script:isWindowsPlatform -and ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))) {
        $blockedKey = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked'
        $blockedExisted = Test-Path -LiteralPath $blockedKey
        $previousValue = if ($blockedExisted) { (Get-Item -LiteralPath $blockedKey).GetValue($script:v14Clsid) } else { $null }
        $previousValue | Should -BeNullOrEmpty -Because 'the synthetic CLSID must not be pre-blocked on the runner'

        $manifest = New-V14ShellManifest -Id 'e2e.shell.handler.block' `
            -Ops @(@{ type = 'shell.handler.block'; clsid = $script:v14Clsid; reason = 'domovoy v1.4 E2E fixture' }) `
            -Verify @(@{ type = 'shell.handler.blocked'; clsid = $script:v14Clsid })

        $applied = Invoke-DomovoyFeature -ManifestFile $manifest -Apply -SkipRestorePoint
        $applied.Mode | Should -Be 'Apply'
        $applied.Verification.AllPass | Should -BeTrue
        (Get-Item -LiteralPath $blockedKey).GetValue($script:v14Clsid) | Should -Be 'domovoy v1.4 E2E fixture'

        $undo = Undo-DomovoyFeature -Id 'e2e.shell.handler.block' -Apply
        $undo.Mode | Should -Be 'Undo'
        (Get-Item -LiteralPath $blockedKey).GetValue($script:v14Clsid) | Should -BeNullOrEmpty
    }
}
