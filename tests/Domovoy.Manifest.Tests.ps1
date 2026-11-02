BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $featureFiles = @(Get-ChildItem -LiteralPath (Join-Path -Path $repoRoot -ChildPath 'config/features') -Filter '*.json')
    $schemaPath = Join-Path -Path $repoRoot -ChildPath 'schema/features.schema.json'
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
                $op.type | Should -BeIn @('registry.set', 'registry.delete', 'service.startup', 'service.stop') -Because "$file.Name op $($op.type)"
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
