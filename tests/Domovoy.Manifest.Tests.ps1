BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $featureFiles = @(Get-ChildItem -LiteralPath (Join-Path -Path $repoRoot -ChildPath 'config/features') -Filter '*.json')
    $profileFiles = @(Get-ChildItem -LiteralPath (Join-Path -Path $repoRoot -ChildPath 'config/profiles') -Filter '*.json')
    $groupFiles = @(Get-ChildItem -LiteralPath (Join-Path -Path $repoRoot -ChildPath 'config/groups') -Filter '*.json')
    $schemaPath = Join-Path -Path $repoRoot -ChildPath 'schema/features.schema.json'
    $profileSchemaPath = Join-Path -Path $repoRoot -ChildPath 'schema/profiles.schema.json'
    $groupSchemaPath = Join-Path -Path $repoRoot -ChildPath 'schema/groups.schema.json'
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
                $op.type | Should -BeIn @('registry.set', 'registry.delete', 'service.startup', 'service.stop', 'appx.remove', 'file.attribute', 'scheduler.task', 'network.dns', 'network.proxy', 'file.timestamp', 'shell.handler.remove', 'shell.handler.block', 'shell.openwith.remove') -Because "$file.Name op $($op.type)"
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
            'appx.absent', 'appx.present', 'file.attributes', 'scheduler.taskState', 'network.dns', 'network.proxy', 'file.timestamp', 'shell.handler.absent', 'shell.handler.blocked', 'shell.openwith.absent'
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

Describe 'Feature groups' {

    It 'repository contains at least one group' {
        $groupFiles.Count | Should -BeGreaterThan 0
    }

    It 'every group has all required fields and a content source' {
        foreach ($file in $groupFiles) {
            $g = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($field in @('id', 'title', 'maxRisk', 'description')) {
                $g.PSObject.Properties[$field] | Should -Not -BeNullOrEmpty -Because "$file.Name must define $field"
            }
            $hasContent = $false
            foreach ($field in @('dependsOn', 'profiles', 'features')) {
                $prop = $g.PSObject.Properties[$field]
                if ($prop -and $null -ne $prop.Value -and @($prop.Value).Count -gt 0) { $hasContent = $true }
            }
            $hasContent | Should -BeTrue -Because "$file.Name must pull at least one profile or feature"
        }
    }

    It 'every group validates against the group JSON schema' {
        foreach ($file in $groupFiles) {
            {
                Test-Json -Json (Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8) -SchemaFile $groupSchemaPath
            } | Should -Not -Throw -Because "$file.Name must match the schema"
        }
    }

    It 'group ids are unique' {
        $ids = foreach ($file in $groupFiles) {
            (Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json).id
        }
        @($ids).Count | Should -Be (@($ids) | Select-Object -Unique).Count
    }

    It 'every dependency, profile and feature reference resolves' {
        $groupIds = foreach ($file in $groupFiles) {
            (Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json).id
        }
        $profileIds = foreach ($file in $profileFiles) {
            (Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json).id
        }
        $featureIds = foreach ($file in $featureFiles) {
            (Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json).id
        }
        foreach ($file in $groupFiles) {
            $g = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            # An absent optional list yields @($null) - filter it out before
            # the membership assertion.
            foreach ($dep in (@($g.PSObject.Properties['dependsOn'].Value) | Where-Object { $_ })) {
                $dep | Should -BeIn $groupIds -Because "$file.Name depends on $dep"
            }
            foreach ($prof in (@($g.PSObject.Properties['profiles'].Value) | Where-Object { $_ })) {
                $prof | Should -BeIn $profileIds -Because "$file.Name references profile $prof"
            }
            foreach ($feat in (@($g.PSObject.Properties['features'].Value) | Where-Object { $_ })) {
                $feat | Should -BeIn $featureIds -Because "$file.Name references feature $feat"
            }
        }
    }

    It 'no group content exceeds the group risk ceiling' {
        $riskOrder = @{ low = 0; medium = 1; high = 2 }
        $featureRisks = @{}
        foreach ($file in $featureFiles) {
            $m = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            $featureRisks[$m.id] = $m.risk
        }
        $profileCeilings = @{}
        foreach ($file in $profileFiles) {
            $p = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            $profileCeilings[$p.id] = $p.maxRisk
        }
        foreach ($file in $groupFiles) {
            $g = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($feat in @($g.PSObject.Properties['features'].Value)) {
                $riskOrder[$featureRisks[$feat]] | Should -BeLessOrEqual $riskOrder[$g.maxRisk] -Because "$file.Name (max $($g.maxRisk)) includes $feat ($($featureRisks[$feat]))"
            }
            foreach ($prof in @($g.PSObject.Properties['profiles'].Value)) {
                $riskOrder[$profileCeilings[$prof]] | Should -BeLessOrEqual $riskOrder[$g.maxRisk] -Because "$file.Name (max $($g.maxRisk)) pulls profile $prof (max $($profileCeilings[$prof]))"
            }
        }
    }

    It 'the bundled group graph has no cycles' {
        # A tiny DFS over the parsed JSON: cycle detection mirrors the
        # runtime resolver so a broken bundle fails before it ships.
        $graph = @{}
        foreach ($file in $groupFiles) {
            $g = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            $deps = @($g.PSObject.Properties['dependsOn'].Value) | Where-Object { $_ }
            $graph[$g.id] = @($deps)
        }
        function Test-DomovoyCycle {
            param([string]$NodeId, [string[]]$Path)
            if (@($Path) -contains $NodeId) {
                throw "cycle: $((@($Path) + $NodeId) -join ' -> ')"
            }
            if ($script:manifestVisited -contains $NodeId) { return }
            $script:manifestVisited += $NodeId
            foreach ($dep in $graph[$NodeId]) {
                Test-DomovoyCycle -NodeId $dep -Path (@($Path) + $NodeId)
            }
        }
        $script:manifestVisited = @()
        foreach ($id in $graph.Keys) {
            { Test-DomovoyCycle -NodeId $id -Path @() } | Should -Not -Throw -Because 'the bundled group graph must stay acyclic'
        }
    }
}
