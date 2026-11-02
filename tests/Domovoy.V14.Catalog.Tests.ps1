# Domovoy v1.4.0 catalog tests: the read-only SmartScreen and SMB signing
# audit (catalog 95) and the Edge Update service manifests (catalog 77).

# NOTE: the variable must not be named *isWindows* - that name collides
# with the read-only automatic $IsWindows (names are case-insensitive).
# Pester 5 evaluates -Skip during DISCOVERY, before BeforeAll runs - the
# flag must be a file-level assignment, or every platform gate reads an
# undefined variable and silently loses its meaning.
$script:isWindowsPlatform = ($PSVersionTable.PSVersion.Major -lt 6) -or $IsWindows

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $env:DOMOVOY_STORE = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("domovoy-v14-catalog-" + [guid]::NewGuid().ToString('N'))
    $env:DOMOVOY_FEATURES_DIR = Join-Path -Path $repoRoot -ChildPath 'config/features'
    Import-Module (Join-Path -Path $repoRoot -ChildPath 'src/Domovoy/Domovoy.psd1') -Force

    $script:v14RepoRoot = $repoRoot
}

AfterAll {
    Remove-Module -Name Domovoy -Force -ErrorAction SilentlyContinue
    if ($env:DOMOVOY_STORE -like "$([System.IO.Path]::GetTempPath())domovoy-v14-catalog-*") {
        Remove-Item -LiteralPath $env:DOMOVOY_STORE -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Edge Update service manifests (catalog 77)' {

    It 'ships both Edge Update service manifests with Manual startup and honest references' {
        foreach ($name in @('057-services-edgeupdate-manual.json', '058-services-edgeupdatem-manual.json')) {
            $path = Join-Path -Path $script:v14RepoRoot -ChildPath "config/features/$name"
            $path | Should -Exist
            $m = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
            $m.category | Should -Be 'services'
            $m.risk | Should -Be 'medium'
            $m.undo.mode | Should -Be 'snapshot'
            $m.ops[0].type | Should -Be 'service.startup'
            $m.ops[0].startupType | Should -Be 'Manual'
            # The honest way: Manual, never Disabled.
            $m.ops[0].startupType | Should -Not -Be 'Disabled'
            @($m.references | Where-Object { $_ -like 'https://learn.microsoft.com/*' }).Count | Should -BeGreaterThan 0
        }
    }

    It 'names exactly the verified Edge Update service document names' {
        $m1 = Get-Content -LiteralPath (Join-Path -Path $script:v14RepoRoot -ChildPath 'config/features/057-services-edgeupdate-manual.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $m2 = Get-Content -LiteralPath (Join-Path -Path $script:v14RepoRoot -ChildPath 'config/features/058-services-edgeupdatem-manual.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $m1.ops[0].name | Should -Be 'edgeupdate'
        $m2.ops[0].name | Should -Be 'edgeupdatem'
        # The elevation service is deliberately out of scope: Microsoft gives
        # it "no guidance" in the service guidance table.
        @($m1.ops + $m2.ops).name | Should -Not -Contain 'MicrosoftEdgeElevationService'
    }
}

Describe 'SmartScreen/SMB audit (catalog 95)' {

    It 'the command exists in the module' {
        Get-Command Get-DomovoySmartScreenStatus -Module Domovoy | Should -Not -BeNullOrEmpty
    }

    It 'on non-Windows it refuses loudly instead of touching a registry' -Skip:$script:isWindowsPlatform {
        { Get-DomovoySmartScreenStatus } | Should -Throw '*requires Windows*'
    }

    It 'on Windows it returns one honest row per audited setting plus a summary' -Skip:(-not $script:isWindowsPlatform) {
        $report = Get-DomovoySmartScreenStatus
        @($report.Rows).Count | Should -Be 5

        $valueNames = @($report.Rows | ForEach-Object { $_.ValueName })
        $valueNames | Should -Contain 'EnableSmartScreen'
        $valueNames | Should -Contain 'SmartScreenEnabled'
        $valueNames | Should -Contain 'RequireSecuritySignature'
        # Server (LanManServer) and client (LanManWorkstation) sides separately.
        @($report.Rows | Where-Object { $_.ValueName -eq 'RequireSecuritySignature' }).Count | Should -Be 2

        $report.Summary | Should -Not -BeNullOrEmpty
        $report.Summary.SettingsAudited | Should -Be 5

        foreach ($row in @($report.Rows)) {
            $row.Path | Should -BeLike 'HKLM:*'
            # A missing value is the honest '<unset>' sentinel, never empty.
            $row.Value | Should -Not -BeNullOrEmpty
            $row.Verdict | Should -Not -BeNullOrEmpty
        }
    }
}
