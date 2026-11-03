<#
.SYNOPSIS
    Packaging contract of the portable single-file launcher (v1.5.3).

.DESCRIPTION
    The portable exe is built from three cooperating files: the C# launcher
    (packaging/shim/DomovoyPortable.cs), the Windows builder
    (tools/Build-PortableExe.ps1) and the release workflow
    (.github/workflows/release.yml). This suite machine-checks the contract
    between them on every CI run, so a rename or a dropped gate cannot
    drift through silently: the embedded-resource names must match between
    the C# source and the builder, the launcher must resolve the payload
    shims, and the workflow must compile, smoke-test and ship the asset.
#>
Describe 'Portable launcher packaging contract' {
    BeforeAll {
        $repoRoot = Split-Path -Parent $PSScriptRoot
        $launcherPath = Join-Path $repoRoot 'packaging/shim/DomovoyPortable.cs'
        $builderPath = Join-Path $repoRoot 'tools/Build-PortableExe.ps1'
        $manifestPath = Join-Path $repoRoot 'packaging/shim/DomovoyPortable.manifest'
        $workflowPath = Join-Path $repoRoot '.github/workflows/release.yml'

        $launcher = Get-Content -LiteralPath $launcherPath -Raw
        $builder = Get-Content -LiteralPath $builderPath -Raw
        $workflow = Get-Content -LiteralPath $workflowPath -Raw
    }

    It 'the launcher source exists with the manifest and the builder' {
        Test-Path -LiteralPath $launcherPath -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath $manifestPath -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath $builderPath -PathType Leaf | Should -BeTrue
    }

    It 'embeds the payload under the contract resource names' {
        $launcher | Should -Match 'Domovoy\.Portable\.payload\.zip'
        $launcher | Should -Match 'Domovoy\.Portable\.payload\.version'
    }

    It 'builder produces exactly those contract-named resources' {
        $builder | Should -Match 'Domovoy\.Portable\.payload\.zip'
        $builder | Should -Match 'Domovoy\.Portable\.payload\.version'
    }

    It 'launcher selftest requires the full release payload layout' {
        foreach ($rel in @('README\.md', 'LICENSE', 'Domovoy/Domovoy\.psd1', 'Domovoy/Domovoy\.psm1', 'Domovoy/domovoy\.ps1', 'Domovoy/domovoy\.exe')) {
            $launcher | Should -Match $rel
        }
    }

    It 'launcher selftest compares the module manifest version with the payload version' {
        $launcher | Should -Match 'ModuleVersion'
        $launcher | Should -Match 'SelfTest FAIL'
        $launcher | Should -Match 'SelfTest PASS'
    }

    It 'launcher stays C#5 - no string interpolation, no null-conditional' {
        $launcher | Should -Not -Match '\$"'
        $launcher | Should -Not -Match '\?\.'
    }

    It 'release workflow compiles, smoke-tests and ships the portable exe' {
        $workflow | Should -Match 'portable-exe:'
        $workflow | Should -Match 'Build-PortableExe\.ps1'
        $workflow | Should -Match '--selftest'
        $workflow | Should -Match 'Portable\.exe\.sha256'
    }

    It 'release job waits for the portable job and downloads its artifact' {
        $workflow | Should -Match 'needs: \[await-tests, shim-exe, portable-exe\]'
        $workflow | Should -Match 'name: domovoy-portable'
    }
}
