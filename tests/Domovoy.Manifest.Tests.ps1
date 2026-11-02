BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $featureFiles = @(Get-ChildItem -LiteralPath (Join-Path -Path $repoRoot -ChildPath 'config/features') -Filter '*.json')
    $profileFiles = @(Get-ChildItem -LiteralPath (Join-Path -Path $repoRoot -ChildPath 'config/profiles') -Filter '*.json')
    $schemaPath = Join-Path -Path $repoRoot -ChildPath 'schema/features.schema.json'
    $profileSchemaPath = Join-Path -Path $repoRoot -ChildPath 'schema/profiles.schema.json'
}

Describe 'Feature manifests' {

    It 'repository contains at least one feature manifest' {
        $featureFiles.Count | Should -BeGreaterThan 0
    }

    It 'every manifest has all required fields' {
        foreach ($file in $featureFiles) {
            $m = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($field in @('id', 'title', 'version', 'category', 'risk', 'description', 'ops', 'undo', 'verify', 'references')) {
                $m.PSObject.Properties[$field] | Should -Not -BeNullOrEmpty -Because "$file.Name must define $field"
            }
        }
    }

    It 'all manifest ids are unique' {
        $ids = foreach ($file in $featureFiles) {
            (Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json).id
        }
        @($ids).Count | Should -Be (@($ids) | Select-Object -Unique).Count
    }

    It 'all manifest ids match the naming convention' {
        foreach ($file in $featureFiles) {
            $id = (Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json).id
            $id | Should -Match '^[a-z0-9]+(\.[a-z0-9-]+)+$'
        }
    }

    It 'all ops use supported op types' {
        foreach ($file in $featureFiles) {
            $m = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($op in @($m.ops)) {
                $op.type | Should -BeIn @('registry.set', 'registry.delete', 'service.startup', 'service.stop', 'appx.remove', 'file.attribute', 'scheduler.task') -Because "$file.Name op $($op.type)"
            }
        }
    }

    It 'undo mode is snapshot in every manifest' {
        foreach ($file in $featureFiles) {
            $m = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            $m.undo.mode | Should -Be 'snapshot' -Because "$file.Name must be reversible"
        }
    }

    It 'every manifest has at least one verify probe' {
        foreach ($file in $featureFiles) {
            $m = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            @($m.verify).Count | Should -BeGreaterThan 0 -Because "$file.Name must be verifiable"
        }
    }

    It 'every verify probe type is implemented in Test-DomovoyEffect (100% coverage)' {
        # Keep this list in sync with the switch statement in
        # Test-DomovoyEffect. A new probe type must be implemented there and
        # listed here in the same change.
        $implemented = @(
            'registry.set', 'registry.absent', 'service.startup', 'service.status',
            'appx.absent', 'appx.present', 'file.attributes', 'scheduler.taskState'
        )
        foreach ($file in $featureFiles) {
            $m = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($probe in @($m.verify)) {
                $probe.type | Should -BeIn $implemented -Because "$file.Name probe $($probe.type)"
            }
        }
    }

    It 'all references are https links' {
        foreach ($file in $featureFiles) {
            $m = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($ref in @($m.references)) {
                $ref | Should -BeLike 'https://*' -Because "$file.Name references"
            }
        }
    }

    It 'every manifest validates against the JSON schema' {
        foreach ($file in $featureFiles) {
            {
                Test-Json -Json (Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8) -SchemaFile $schemaPath
            } | Should -Not -Throw -Because "$file.Name must match the schema"
        }
    }
}

Describe 'Feature profiles' {

    It 'repository contains at least one profile' {
        $profileFiles.Count | Should -BeGreaterThan 0
    }

    It 'every profile has all required fields' {
        foreach ($file in $profileFiles) {
            $p = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($field in @('id', 'title', 'maxRisk', 'description', 'features')) {
                $p.PSObject.Properties[$field] | Should -Not -BeNullOrEmpty -Because "$file.Name must define $field"
            }
        }
    }

    It 'every profile validates against the profile JSON schema' {
        foreach ($file in $profileFiles) {
            {
                Test-Json -Json (Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8) -SchemaFile $profileSchemaPath
            } | Should -Not -Throw -Because "$file.Name must match the profile schema"
        }
    }

    It 'every profile feature id resolves to a real manifest' {
        $knownIds = foreach ($file in $featureFiles) {
            (Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json).id
        }
        foreach ($file in $profileFiles) {
            $p = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($featureId in @($p.features)) {
                $featureId | Should -BeIn $knownIds -Because "$file.Name references $featureId"
            }
        }
    }

    It 'no profile feature exceeds the profile risk ceiling' {
        $riskOrder = @{ low = 0; medium = 1; high = 2 }
        $risks = @{}
        foreach ($file in $featureFiles) {
            $m = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            $risks[$m.id] = $m.risk
        }
        foreach ($file in $profileFiles) {
            $p = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($featureId in @($p.features)) {
                $riskOrder[$risks[$featureId]] | Should -BeLessOrEqual $riskOrder[$p.maxRisk] -Because "$file.Name (max $($p.maxRisk)) includes $featureId ($($risks[$featureId]))"
            }
        }
    }

    It 'profile ids are unique' {
        $ids = foreach ($file in $profileFiles) {
            (Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json).id
        }
        @($ids).Count | Should -Be (@($ids) | Select-Object -Unique).Count
    }
}
