BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $env:DOMOVOY_STORE = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("domovoy-profile-" + [guid]::NewGuid().ToString('N'))
    $env:DOMOVOY_FEATURES_DIR = Join-Path -Path $repoRoot -ChildPath 'config/features'
    $env:DOMOVOY_PROFILES_DIR = Join-Path -Path $repoRoot -ChildPath 'config/profiles'
    Import-Module (Join-Path -Path $repoRoot -ChildPath 'src/Domovoy/Domovoy.psd1') -Force

    $script:testRoot = 'HKCU:\Software\DomovoyCI\' + [guid]::NewGuid().ToString('N').Substring(0, 8)
    New-Item -Path $script:testRoot -ItemType Directory -Force | Out-Null

    $script:manifestDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("domovoy-profile-manifests-" + [guid]::NewGuid().ToString('N'))
    New-Item -Path $script:manifestDir -ItemType Directory -Force | Out-Null

    $script:profileDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("domovoy-profile-defs-" + [guid]::NewGuid().ToString('N'))
    New-Item -Path $script:profileDir -ItemType Directory -Force | Out-Null

    $registryRef = 'https://learn.microsoft.com/windows/win32/sysinfo/registry'

    $lowManifest = Join-Path -Path $script:manifestDir -ChildPath 'fixture-low.json'
    @{
        id = 'fixture.low.value'
        title = 'Test fixture: low-risk registry set'
        version = '1.0.0'
        category = 'core'
        risk = 'low'
        description = 'Test fixture: sets a DWORD value on a temporary registry key.'
        ops = @(@{ type = 'registry.set'; path = $script:testRoot; name = 'LowValue'; value = 11; valueType = 'DWord' })
        undo = @{ mode = 'snapshot' }
        verify = @(@{ type = 'registry.set'; path = $script:testRoot; name = 'LowValue'; value = 11 })
        references = @($registryRef)
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $lowManifest -Encoding UTF8

    $mediumManifest = Join-Path -Path $script:manifestDir -ChildPath 'fixture-medium.json'
    @{
        id = 'fixture.medium.value'
        title = 'Test fixture: medium-risk registry set'
        version = '1.0.0'
        category = 'core'
        risk = 'medium'
        description = 'Test fixture: sets a DWORD value on a temporary registry key.'
        ops = @(@{ type = 'registry.set'; path = $script:testRoot; name = 'MediumValue'; value = 22; valueType = 'DWord' })
        undo = @{ mode = 'snapshot' }
        verify = @(@{ type = 'registry.set'; path = $script:testRoot; name = 'MediumValue'; value = 22 })
        references = @($registryRef)
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $mediumManifest -Encoding UTF8

    $highManifest = Join-Path -Path $script:manifestDir -ChildPath 'fixture-high.json'
    @{
        id = 'fixture.high.value'
        title = 'Test fixture: high-risk registry set'
        version = '1.0.0'
        category = 'core'
        risk = 'high'
        description = 'Test fixture: sets a DWORD value on a temporary registry key.'
        ops = @(@{ type = 'registry.set'; path = $script:testRoot; name = 'HighValue'; value = 33; valueType = 'DWord' })
        undo = @{ mode = 'snapshot' }
        verify = @(@{ type = 'registry.set'; path = $script:testRoot; name = 'HighValue'; value = 33 })
        references = @($registryRef)
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $highManifest -Encoding UTF8

    $profileManifest = Join-Path -Path $script:profileDir -ChildPath 'fixture-profile.json'
    @{
        id = 'fixture.profile'
        title = 'Fixture profile'
        maxRisk = 'low'
        description = 'Test fixture: a low risk ceiling over three fixture features of mixed risk.'
        features = @('fixture.low.value', 'fixture.medium.value', 'fixture.high.value')
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $profileManifest -Encoding UTF8
}

AfterAll {
    Remove-Module -Name Domovoy -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $script:testRoot) {
        Remove-Item -LiteralPath $script:testRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $script:manifestDir) {
        Remove-Item -LiteralPath $script:manifestDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $script:profileDir) {
        Remove-Item -LiteralPath $script:profileDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($env:DOMOVOY_STORE -and (Test-Path -LiteralPath $env:DOMOVOY_STORE)) {
        Remove-Item -LiteralPath $env:DOMOVOY_STORE -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Domovoy profiles' {

    It 'cautious profile produces a full dry-run plan without skipping anything' {
        $result = Invoke-DomovoyProfile -Id 'cautious'
        $result.Profile | Should -Be 'cautious'
        $result.Mode | Should -Be 'DryRun'
        @($result.Applied).Count | Should -Be 15
        @($result.Skipped).Count | Should -Be 0
        $result.Applied[0].Mode | Should -Be 'DryRun'
    }

    It 'standard profile plans every bundled feature' {
        $result = Invoke-DomovoyProfile -Id 'standard'
        $result.Profile | Should -Be 'standard'
        @($result.Applied).Count | Should -Be 21
        @($result.Skipped).Count | Should -Be 0
    }

    It 'unknown profile id throws' {
        { Invoke-DomovoyProfile -Id 'no.such.profile' } | Should -Throw
    }

    It 'risk ceiling skips higher-risk features and reports them honestly' {
        $oldFeatures = $env:DOMOVOY_FEATURES_DIR
        $oldProfiles = $env:DOMOVOY_PROFILES_DIR
        $env:DOMOVOY_FEATURES_DIR = $script:manifestDir
        $env:DOMOVOY_PROFILES_DIR = $script:profileDir
        try {
            $result = Invoke-DomovoyProfile -Id 'fixture.profile' -Apply -SkipRestorePoint
            $result.Mode | Should -Be 'Apply'
            @($result.Applied).Count | Should -Be 1
            $result.Applied[0].Feature | Should -Be 'fixture.low.value'
            $result.Applied[0].Mode | Should -Be 'Apply'

            @($result.Skipped).Count | Should -Be 2
            $result.Skipped.Feature | Should -Contain 'fixture.medium.value'
            $result.Skipped.Feature | Should -Contain 'fixture.high.value'
            $result.Skipped[0].Reason | Should -Match 'exceeds profile max'

            (Get-ItemProperty -LiteralPath $script:testRoot).LowValue | Should -Be 11
            Get-ItemProperty -LiteralPath $script:testRoot -Name 'MediumValue' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
            Get-ItemProperty -LiteralPath $script:testRoot -Name 'HighValue' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        }
        finally {
            $env:DOMOVOY_FEATURES_DIR = $oldFeatures
            $env:DOMOVOY_PROFILES_DIR = $oldProfiles
        }
    }
}
