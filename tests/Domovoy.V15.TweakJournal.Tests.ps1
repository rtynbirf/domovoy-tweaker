#Requires -Version 5.1
<#
.SYNOPSIS
    П39 (issue #20) · приёмка машиной: «твик -> откат -> реестр байт-в-байт
    равен исходному» — для каждого твика; PSScriptAnalyzer warnings=0.

.DESCRIPTION
    Уровни доказательства:
      1. Все 58 манифестов config/features/*.json прогоняются на
         память-складе (memory backend): apply -> undo -> канонический
         дамп склада байт-в-байт равен исходному. Манифесты с операциями
         вне whitelist (appx.remove, scheduler.task, network.*) обязаны
         отказать fail-closed ДО любой мутации (склад остаётся нетронутым).
      2. Живой реестр (только Windows): полный цикл на отдельном
         черновом ключе HKCU с шестью типами значений и создаваемым
         подключом; равенство доказывается reg.exe-экспортом до/после
         (SHA256 файлов экспорта) — байт-в-байт буквально.
      3. Гарантия отката: журнал с упреждением; откат частично
         применённой партии (обрыв на середине) чинит склад до байта;
         повторный твик без отката предыдущего запрещён; undo без -Apply
         — сухой прогон.
      4. PSScriptAnalyzer по настройкам репо: 0 ошибок И 0 предупреждений
         на новом исполнителе (PS 5.1+; на не-Windows пропускается честно).

    Pester 5: всё состояние живёт в BeforeAll (фазы discovery и run
    разделены), цикл по манифестам — data-driven It -ForEach.
#>

Describe 'П39 · твик-журнал с гарантированным откатом' {
    # список манифестов нужен на стадии discovery: им порождаются It-кейсы
    $manifestFiles = @(
        Get-ChildItem -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..' | Join-Path -ChildPath 'config' | Join-Path -ChildPath 'features') -Filter '*.json' |
            Sort-Object Name |
            ForEach-Object { @{ Path = $_.FullName; Name = $_.BaseName } }
    )

    BeforeAll {
        $Tool = (Join-Path -Path $PSScriptRoot -ChildPath '..' | Join-Path -ChildPath 'tools' | Join-Path -ChildPath 'Invoke-DomovoyTweakJournal.ps1')
        $Features = (Join-Path -Path $PSScriptRoot -ChildPath '..' | Join-Path -ChildPath 'config' | Join-Path -ChildPath 'features')
        $Settings = (Join-Path -Path $PSScriptRoot -ChildPath '..' | Join-Path -ChildPath 'PSScriptAnalyzerSettings.psd1')
        $SupportedOps = @('registry.set', 'service.startup')

        function New-WorkDir {
            $dir = Join-Path ([IO.Path]::GetTempPath()) ("domovoy-p39-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            return $dir
        }

        function Get-SeedValue {
            # значение-пока-старое, гарантированно отличное от нового
            param([object]$Op)
            $kind = 'DWord'
            if ($Op.PSObject.Properties['valueType']) { $kind = $Op.valueType }
            switch ($kind) {
                'DWord'        { $v = if ("$($Op.value)" -eq '1') { 0 } else { 1 }; return , @{ kind = 'DWord'; value = $v } }
                'QWord'        { $v = if ("$($Op.value)" -eq '1') { 0 } else { 1 }; return , @{ kind = 'QWord'; value = $v } }
                'Binary'       { return , @{ kind = 'Binary'; value = @(9, 8, 7) } }
                'MultiString'  { return , @{ kind = 'MultiString'; value = @('старый', 'ряд') } }
                'ExpandString' { return , @{ kind = 'ExpandString'; value = 'старое-значение' } }
                default        { return , @{ kind = 'String'; value = 'старое-значение' } }
            }
        }

        function Write-SeedStore {
            # склад до твика: каждая операция манифеста уже имеет «старое значение»
            param([string]$Path, [object]$ManifestData)
            $paths = [pscustomobject]@{}
            $services = [pscustomobject]@{}
            foreach ($op in $ManifestData.ops) {
                if ($op.type -eq 'registry.set') {
                    $seed = Get-SeedValue -Op $op
                    $p = $paths.PSObject.Properties[$op.path]
                    if (-not $p) {
                        $paths | Add-Member -MemberType NoteProperty -Name $op.path -Value ([pscustomobject]@{ existed = $true; values = [pscustomobject]@{} })
                        $p = $paths.PSObject.Properties[$op.path]
                    }
                    $p.Value.values | Add-Member -MemberType NoteProperty -Name $op.name -Value ([pscustomobject]@{ kind = $seed.kind; value = $seed.value })
                }
                if ($op.type -eq 'service.startup') {
                    $services | Add-Member -MemberType NoteProperty -Name $op.name -Value ([pscustomobject]@{ startup = 'Automatic' })
                }
            }
            ([pscustomobject]@{ paths = $paths; services = $services }) |
                ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
        }

        function Get-CanonicalStoreText {
            # канонический дамп склада: сортировка ключей, числа и строки как текст
            param([string]$Path)
            $store = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
            $lines = @()
            foreach ($p in ($store.paths.PSObject.Properties | Sort-Object Name)) {
                $lines += "path|$($p.Name)|existed=$($p.Value.existed)"
                foreach ($v in ($p.Value.values.PSObject.Properties | Sort-Object Name)) {
                    $val = $v.Value.value
                    $text = if ($null -eq $val) { '<null>' } elseif ($val -is [System.Array]) { (@($val) | ForEach-Object { "$_" }) -join ',' } else { "$val" }
                    $lines += "  value|$($v.Name)|$($v.Value.kind)=$text"
                }
            }
            foreach ($s in ($store.services.PSObject.Properties | Sort-Object Name)) {
                $lines += "service|$($s.Name)|$($s.Value.startup)"
            }
            return ($lines -join "`n")
        }
    }

    Context 'манифест-схема: каждый твик описан декларативно' {
        It 'исполнитель на месте и проверяет форму любого манифеста' {
            Test-Path -LiteralPath $Tool | Should -BeTrue
            $m = Join-Path $Features '001-disable-diagtrack.json'
            $r = & $Tool -Check -Manifest $m
            $r.Verdict | Should -Be 'shape-ok'
        }

        It 'битая форма манифеста отклоняется (fail-closed)' {
            $dir = New-WorkDir
            $bad = Join-Path $dir 'bad.json'
            '{"id":"x","ops":[{"type":"registry.set","path":"HKCU:\\Software\\x"}]}' |
                Set-Content -LiteralPath $bad -Encoding UTF8
            { & $Tool -Check -Manifest $bad } | Should -Throw
        }
    }

    Context 'все твики: apply -> undo -> байт-в-байт равен исходному (память-склад)' {
        It 'твик <Name> — откат возвращает склад байт-в-байт' -ForEach $manifestFiles {
            $data = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
            $supported = @($data.ops | Where-Object { $SupportedOps -contains $_.type }).Count
            $dir = New-WorkDir
            $store = Join-Path $dir 'store.json'
            $journal = Join-Path $dir 'journal.jsonl'

            if ($supported -lt @($data.ops).Count) {
                # операции вне whitelist: исполнитель обязан отказать ДО мутаций
                Write-SeedStore -Path $store -ManifestData $data
                $before = Get-CanonicalStoreText -Path $store
                { & $Tool -Manifest $Path -JournalPath $journal -Backend memory -MemoryStorePath $store } |
                    Should -Throw '*whitelist*'
                Get-CanonicalStoreText -Path $store | Should -Be $before
                return
            }

            Write-SeedStore -Path $store -ManifestData $data
            $before = Get-CanonicalStoreText -Path $store

            $applied = & $Tool -Manifest $Path -JournalPath $journal -Backend memory -MemoryStorePath $store
            $applied.Ops | Should -Be @($data.ops).Count
            $after = Get-CanonicalStoreText -Path $store
            $after | Should -Not -Be $before   # твик действительно меняет мир

            $undone = & $Tool -Undo -Apply -JournalPath $journal -Backend memory -MemoryStorePath $store
            $undone.Mode | Should -Be 'Undone'
            $undone.Restored | Should -Be @($data.ops).Count
            Get-CanonicalStoreText -Path $store | Should -Be $before   # байт-в-байт
        }
    }

    Context 'гарантия отката: журнал помнит, даже когда применение оборвалось' {
        It 'откат частично применённой партии чинит склад до байта' {
            $dir = New-WorkDir
            $store = Join-Path $dir 'store.json'
            $journal = Join-Path $dir 'journal.jsonl'
            $pathKey = 'HKCU:\Software\DomovoyP39Test\Partial'
            # склад: значение существовало (DWord 7); «применение» поставило 0 и оборвалось
            ([pscustomobject]@{
                paths = [pscustomobject]@{ $pathKey = [pscustomobject]@{ existed = $true; values = [pscustomobject]@{ Val = [pscustomobject]@{ kind = 'DWord'; value = 0 } } } }
                services = [pscustomobject]@{}
            }) | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $store -Encoding UTF8
            # журнал: op.begin (старое 7) + op.applied — и обрыв: batch.done нет
            $b = 'crashbatch01'
            @(
                @{ v = 1; event = 'op.begin'; batch = $b; feature = 'test.crash'; op = 'registry.set'; path = $pathKey; name = 'Val'; old = @{ present = $true; kind = 'DWord'; value = 7; pathExisted = $true }; ts = '2026-11-11T00:00:00.0000000Z' }
                @{ v = 1; event = 'op.applied'; batch = $b; op = 'registry.set'; ts = '2026-11-11T00:00:01.0000000Z' }
            ) | ForEach-Object { ($_ | ConvertTo-Json -Compress -Depth 8) | Add-Content -LiteralPath $journal -Encoding UTF8 }

            $beforeDry = Get-CanonicalStoreText -Path $store
            $plan = & $Tool -Undo -JournalPath $journal -Backend memory -MemoryStorePath $store
            $plan.Mode | Should -Be 'DryRun'
            Get-CanonicalStoreText -Path $store | Should -Be $beforeDry   # сухой прогон не меняет склад

            & $Tool -Undo -Apply -JournalPath $journal -Backend memory -MemoryStorePath $store | Out-Null
            $fixed = Get-Content -LiteralPath $store -Raw -Encoding UTF8 | ConvertFrom-Json
            $fixed.paths.$pathKey.values.Val.value | Should -Be 7          # старое вернулось
            (Get-Content -LiteralPath $journal -Encoding UTF8 | Select-String -Pattern 'batch.undone') | Should -Not -BeNullOrEmpty
        }

        It 'повторный твик без отката предыдущего запрещён' {
            $dir = New-WorkDir
            $store = Join-Path $dir 'store.json'
            $journal = Join-Path $dir 'journal.jsonl'
            $m = Join-Path $dir 'm.json'
            '{"id":"test.repeat","title":"x","ops":[{"type":"registry.set","path":"HKCU:\\Software\\DomovoyP39Test\\Repeat","name":"V","value":5,"valueType":"DWord"}]}' |
                Set-Content -LiteralPath $m -Encoding UTF8
            ([pscustomobject]@{ paths = [pscustomobject]@{}; services = [pscustomobject]@{} }) |
                ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $store -Encoding UTF8
            { & $Tool -Manifest $m -JournalPath $journal -Backend memory -MemoryStorePath $store } | Should -Not -Throw
            { & $Tool -Manifest $m -JournalPath $journal -Backend memory -MemoryStorePath $store } |
                Should -Throw '*откат обязателен*'
        }

        It 'дрейф-страж: манифест, солгавший о старом значении, не применяется' {
            $dir = New-WorkDir
            $store = Join-Path $dir 'store.json'
            $journal = Join-Path $dir 'journal.jsonl'
            $pathKey = 'HKCU:\Software\DomovoyP39Test\Drift'
            ([pscustomobject]@{
                paths = [pscustomobject]@{ $pathKey = [pscustomobject]@{ existed = $true; values = [pscustomobject]@{ V = [pscustomobject]@{ kind = 'DWord'; value = 9 } } } }
                services = [pscustomobject]@{}
            }) | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $store -Encoding UTF8
            $m = Join-Path $dir 'm.json'
            '{"id":"test.drift","title":"x","ops":[{"type":"registry.set","path":"HKCU:\\Software\\DomovoyP39Test\\Drift","name":"V","old":5,"value":6,"valueType":"DWord"}]}' |
                Set-Content -LiteralPath $m -Encoding UTF8
            { & $Tool -Manifest $m -JournalPath $journal -Backend memory -MemoryStorePath $store } |
                Should -Throw '*дрейф мира*'
        }
    }

    Context 'живой реестр: твик -> откат -> reg-экспорт байт-в-байт (только Windows)' -Skip:($env:OS -ne 'Windows_NT') {
        BeforeAll {
            $Root = 'HKCU:\Software\DomovoyP39Test\Live'
            if (Test-Path -LiteralPath $Root) { Remove-Item -LiteralPath $Root -Recurse -Force }
            # у New-Item и New-ItemProperty нет -LiteralPath — обычный -Path (без масок)
            New-Item -Path $Root -Force | Out-Null
            New-ItemProperty -Path $Root -Name 'DWordVal' -Value 1 -PropertyType DWord -Force | Out-Null
            New-ItemProperty -Path $Root -Name 'QWordVal' -Value 1234567890123 -PropertyType QWord -Force | Out-Null
            New-ItemProperty -Path $Root -Name 'StrVal' -Value 'старая-строка' -PropertyType String -Force | Out-Null
            New-ItemProperty -Path $Root -Name 'ExpandVal' -Value 'старый-expand' -PropertyType ExpandString -Force | Out-Null
            New-ItemProperty -Path $Root -Name 'BinVal' -Value ([byte[]]@(4, 5, 6)) -PropertyType Binary -Force | Out-Null
            New-ItemProperty -Path $Root -Name 'MultiVal' -Value @('старый', 'мульти') -PropertyType MultiString -Force | Out-Null
        }

        AfterAll {
            if (Test-Path -LiteralPath $Root) { Remove-Item -LiteralPath $Root -Recurse -Force }
        }

        It 'полный цикл: apply меняет, undo возвращает реестр байт-в-байт' {
            $dir = New-WorkDir
            $journal = Join-Path $dir 'journal.jsonl'
            $exportBefore = Join-Path $dir 'before.reg'
            $exportAfter = Join-Path $dir 'after.reg'
            $regPath = 'HKCU\Software\DomovoyP39Test\Live'

            $manifest = Join-Path $dir 'live.json'
            @{
                id = 'test.live'; title = 'live'; ops = @(
                    @{ type = 'registry.set'; path = $Root; name = 'DWordVal'; value = 42; valueType = 'DWord' }
                    @{ type = 'registry.set'; path = $Root; name = 'QWordVal'; value = 9988776655443322; valueType = 'QWord' }
                    @{ type = 'registry.set'; path = $Root; name = 'StrVal'; value = 'новая-строка'; valueType = 'String' }
                    @{ type = 'registry.set'; path = $Root; name = 'ExpandVal'; value = 'новый-expand'; valueType = 'ExpandString' }
                    @{ type = 'registry.set'; path = $Root; name = 'BinVal'; value = @(1, 2, 3, 4); valueType = 'Binary' }
                    @{ type = 'registry.set'; path = $Root; name = 'MultiVal'; value = @('новый', 'мульти'); valueType = 'MultiString' }
                    @{ type = 'registry.set'; path = "$Root\CreatedKey"; name = 'Born'; value = 7; valueType = 'DWord' }
                )
            } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifest -Encoding UTF8

            reg.exe export $regPath $exportBefore /y | Out-Null
            Test-Path -LiteralPath $exportBefore | Should -BeTrue

            $applied = & $Tool -Manifest $manifest -JournalPath $journal
            $applied.Ops | Should -Be 7
            (Get-ItemProperty -LiteralPath $Root).DWordVal | Should -Be 42
            Test-Path -LiteralPath "$Root\CreatedKey" | Should -BeTrue

            $plan = & $Tool -Undo -JournalPath $journal
            $plan.Mode | Should -Be 'DryRun'
            @($plan.Ops).Count | Should -Be 7

            & $Tool -Undo -Apply -JournalPath $journal
            (Get-ItemProperty -LiteralPath $Root).DWordVal | Should -Be 1
            Test-Path -LiteralPath "$Root\CreatedKey" | Should -BeFalse   # созданный твиком ключ снят

            reg.exe export $regPath $exportAfter /y | Out-Null
            (Get-FileHash -LiteralPath $exportBefore -Algorithm SHA256).Hash |
                Should -Be (Get-FileHash -LiteralPath $exportAfter -Algorithm SHA256).Hash   # байт-в-байт
        }
    }

    Context 'PSScriptAnalyzer: предупреждений ноль (приёмка П39)' -Skip:($env:OS -ne 'Windows_NT') {
        It 'исполнитель чист по настройкам репо: 0 ошибок, 0 предупреждений' {
            if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
                Set-ItResult -Skipped -Because 'PSScriptAnalyzer недоступен'
                return
            }
            $results = Invoke-ScriptAnalyzer -Path $Tool -Settings $Settings
            $errors = @($results | Where-Object { $_.Severity -eq 'Error' })
            $warnings = @($results | Where-Object { $_.Severity -eq 'Warning' })
            $errors | Should -BeNullOrEmpty
            $warnings | Should -BeNullOrEmpty
        }
    }
}
