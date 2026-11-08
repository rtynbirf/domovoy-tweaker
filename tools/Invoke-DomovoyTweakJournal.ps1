#Requires -Version 5.1
<#
.SYNOPSIS
    П39: твик = декларативный манифест с гарантированным откатом (undo-журнал).

.DESCRIPTION
    Исполнитель декларативных манифестов твиков: ключ -> старое значение ->
    новое значение. DOMOVOY-ONECLICK.bat и человек лишь зовут этот скрипт.
    Гарантия отката — журнал с упреждающей записью (write-ahead): ПЕРЕД каждой
    мутацией старое состояние ложится в журнал (op.begin), после — отметка
    (op.applied). Откат = обратный проход журнала (LIFO). Если применение
    упало посреди пути — журнал уже держит старые значения, и откат чинит
    частично применённый твик. Повторное применение твика без отката
    предыдущего запрещено («домовой помнит, как всё было»).

    Реестр: тип значения (DWord/QWord/String/ExpandString/Binary/MultiString)
    захватывается и восстанавливается; значение, которого не было, удаляется,
    ключ, созданный твиком, снимается вместе с пустыми предками.
    Служба: захватывается тип запуска (StartMode) и восстанавливается.

    Операции вне whitelist (appx.remove, scheduler.task, network.*, ...) —
    отказ ДО любой мутации (fail-closed): манифест с ними не применяется.

    Бэкенды: registry — живой реестр Windows; memory — JSON-хранилище
    (тесты и самоописание на любой ОС, байт-в-байт сравнение состояний).

.EXAMPLE
    Invoke-DomovoyTweakJournal.ps1 -Manifest config/features/030-theme-dark.json
    Invoke-DomovoyTweakJournal.ps1 -Undo                                  # сухой прогон
    Invoke-DomovoyTweakJournal.ps1 -Undo -Apply -FeatureId theme.dark
    Invoke-DomovoyTweakJournal.ps1 -Check -Manifest config/features/001-disable-diagtrack.json
#>
[CmdletBinding(SupportsShouldProcess)]
[OutputType([pscustomobject])]
param(
    [string]$Manifest,
    [switch]$Undo,
    [switch]$Check,
    [switch]$Apply,
    [string]$FeatureId,
    [string]$JournalPath,
    [ValidateSet('registry', 'memory')]
    [string]$Backend = 'registry',
    [string]$MemoryStorePath
)

$script:SupportedOps = @('registry.set', 'service.startup')
$script:RegistryKinds = @('DWord', 'QWord', 'String', 'ExpandString', 'Binary', 'MultiString')
$script:ServiceStartups = @('Automatic', 'Manual', 'Disabled')

# ---------------------------------------------------------------- журнал ----

function Add-JournalEntry {
    param([string]$Path, [hashtable]$Entry)
    $Entry.ts = (Get-Date).ToUniversalTime().ToString('o')
    $line = $Entry | ConvertTo-Json -Compress -Depth 8
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    Add-Content -LiteralPath $Path -Value $line -Encoding UTF8
}

function Read-Journal {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    $rows = @()
    foreach ($line in (Get-Content -LiteralPath $Path -Encoding UTF8)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $rows += ($line | ConvertFrom-Json)
    }
    return $rows
}

function Get-LastPendingBatch {
    # партия «не откачена», пока в её событиях нет batch.undone — ЗАКРЫТОСТЬ
    # не важна: оборванная посреди пути партия обязана откатываться первой
    # (write-ahead журнал уже держит старые значения). Выбор — LIFO по
    # порядку журнала: последняя неоткаченная партия откатывается первой.
    param([string]$Path, [string]$Id)
    $rows = Read-Journal -Path $Path
    $order = @()
    $batches = @{}
    foreach ($r in $rows) {
        if (-not $batches.ContainsKey($r.batch)) {
            $batches[$r.batch] = @{ feature = ''; events = @() }
            $order += $r.batch
        }
        if ($r.PSObject.Properties['feature'] -and $r.feature) { $batches[$r.batch].feature = $r.feature }
        $batches[$r.batch].events += $r.event
    }
    for ($i = $order.Count - 1; $i -ge 0; $i--) {
        $b = $order[$i]
        $info = $batches[$b]
        if ($info.events -contains 'batch.undone') { continue }
        if (-not $Id -or $info.feature -eq $Id) { return $b }
    }
    return $null
}

# ----------------------------------------------------------- память-склад ----

function Get-MemoryStore {
    param([string]$Path)
    if ($Path -and (Test-Path -LiteralPath $Path)) {
        return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
    }
    return [pscustomobject]@{ paths = [pscustomobject]@{}; services = [pscustomobject]@{} }
}

function Save-MemoryStore {
    param([string]$Path, [object]$Store)
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $Store | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
}

# ------------------------------------------------------------ реестр API ----

function ConvertTo-RegistrySubPath {
    param([string]$PsPath)
    # .NET API улья не принимает ведущий '\': 'HKCU:\Software\X' -> 'Software\X'
    if ($PsPath -like 'HKCU:*') { return @{ hive = [Microsoft.Win32.Registry]::CurrentUser; sub = $PsPath.Substring(5).TrimStart('\') } }
    if ($PsPath -like 'HKLM:*') { return @{ hive = [Microsoft.Win32.Registry]::LocalMachine; sub = $PsPath.Substring(5).TrimStart('\') } }
    throw "П39: путь не HKCU:/HKLM: — $PsPath"
}

function Get-RegistryValueTyped {
    param([string]$PsPath, [string]$Name)
    $map = ConvertTo-RegistrySubPath -PsPath $PsPath
    $key = $map.hive.OpenSubKey($map.sub)
    if ($null -eq $key) { return @{ present = $false; kind = $null; value = $null } }
    try {
        $raw = $key.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        if ($null -eq $raw) { return @{ present = $false; kind = $null; value = $null } }
        return @{
            present = $true
            kind    = $key.GetValueKind($Name).ToString()
            value   = $raw
        }
    }
    finally { $key.Close() }
}

function ConvertTo-RegistryValue {
    # значение манифеста/журнала -> значение для API реестра нужного типа.
    # Коллекции (Binary/MultiString) возвращаются через запятую-обёртку:
    # конвейер PowerShell разворачивает IEnumerable в object[] (CI run 97:
    # SetValue отверг object[] с ArgumentException), обёртка сохраняет тип.
    param([string]$Kind, [object]$Value)
    switch ($Kind) {
        'DWord'        { return [int32]$Value }
        'QWord'        { return [int64]$Value }
        'String'       { return [string]$Value }
        'ExpandString' { return [string]$Value }
        'Binary'       { return ,([byte[]][int[]]@($Value)) }
        'MultiString'  { return ,([string[]]@($Value)) }
        default        { throw "П39: неизвестный тип значения: $Kind" }
    }
}

function Set-RegistryValueTyped {
    # пишет значение нужного типа; ключ создаётся при отсутствии
    param([string]$PsPath, [string]$Name, [string]$Kind, [object]$Value)
    $map = ConvertTo-RegistrySubPath -PsPath $PsPath
    $key = $map.hive.CreateSubKey($map.sub)
    try {
        $typed = ConvertTo-RegistryValue -Kind $Kind -Value $Value
        $kindEnum = [Microsoft.Win32.RegistryValueKind]$Kind
        $key.SetValue($Name, $typed, $kindEnum)
    }
    finally { $key.Close() }
}

function Remove-RegistryValueTyped {
    param([string]$PsPath, [string]$Name)
    $map = ConvertTo-RegistrySubPath -PsPath $PsPath
    $key = $map.hive.OpenSubKey($map.sub, $true)
    if ($null -eq $key) { return }
    try {
        if (@($key.GetValueNames()) -contains $Name) {
            $key.DeleteValue($Name)
        }
    }
    finally { $key.Close() }
}

function Remove-RegistryKeyIfEmpty {
    # снимает ключ только если он пуст: детей нет и значений нет
    param([string]$PsPath)
    $map = ConvertTo-RegistrySubPath -PsPath $PsPath
    $parent = $map.hive.OpenSubKey((Split-Path -Parent $map.sub), $true)
    if ($null -eq $parent) { return }
    try {
        $leaf = Split-Path -Leaf $map.sub
        if (@($parent.GetSubKeyNames()) -notcontains $leaf) { return }
        $child = $parent.OpenSubKey($leaf)
        if ($null -eq $child) { return }
        try {
            $hasChildren = @($child.GetSubKeyNames()).Count -gt 0
            $hasValues = @($child.GetValueNames()).Count -gt 0
        }
        finally { $child.Close() }
        if ($hasChildren -or $hasValues) {
            throw "П39: ключ $PsPath не пуст — домовой не сносит непустые комнаты"
        }
        $parent.DeleteSubKeyTree($leaf)
    }
    finally { $parent.Close() }
}

# ------------------------------------------------------------ операции твика ----

function Get-TweakOldState {
    param([object]$Op, [string]$Backend, [object]$MemStore)
    if ($Backend -eq 'memory') {
        if ($Op.type -eq 'registry.set') {
            $p = $MemStore.paths.PSObject.Properties[$Op.path]
            if (-not $p) { return @{ present = $false; kind = $null; value = $null; pathExisted = $false } }
            $v = $p.Value.values.PSObject.Properties[$Op.name]
            if (-not $v) { return @{ present = $false; kind = $null; value = $null; pathExisted = [bool]$p.Value.existed } }
            return @{ present = $true; kind = $v.Value.kind; value = $v.Value.value; pathExisted = [bool]$p.Value.existed }
        }
        if ($Op.type -eq 'service.startup') {
            $s = $MemStore.services.PSObject.Properties[$Op.name]
            if (-not $s) { return @{ present = $false; startup = $null } }
            return @{ present = $true; startup = $s.Value.startup }
        }
    }
    if ($Op.type -eq 'registry.set') {
        $old = Get-RegistryValueTyped -PsPath $Op.path -Name $Op.name
        $map = ConvertTo-RegistrySubPath -PsPath $Op.path
        $probe = $map.hive.OpenSubKey($map.sub)
        if ($probe) { $probe.Close() }
        $old.pathExisted = ($null -ne $probe)
        return $old
    }
    if ($Op.type -eq 'service.startup') {
        $svc = Get-CimInstance -ClassName Win32_Service -Filter "Name='$($Op.name)'" -ErrorAction Stop
        if ($null -eq $svc) { return @{ present = $false; startup = $null } }
        $mode = if ($svc.StartMode -eq 'Auto') { 'Automatic' } else { $svc.StartMode }
        return @{ present = $true; startup = $mode }
    }
    throw "П39: операция $($Op.type) не поддерживается"
}

function Set-TweakNewState {
    param([object]$Op, [string]$Backend, [object]$MemStore, [string]$MemStorePath)
    if ($Backend -eq 'memory') {
        if ($Op.type -eq 'registry.set') {
            $p = $MemStore.paths.PSObject.Properties[$Op.path]
            if (-not $p) {
                $MemStore.paths | Add-Member -MemberType NoteProperty -Name $Op.path -Value ([pscustomobject]@{ existed = $false; values = [pscustomobject]@{} })
                $p = $MemStore.paths.PSObject.Properties[$Op.path]
            }
            $kind = if ($Op.PSObject.Properties['valueType']) { $Op.valueType } else { 'DWord' }
            $v = $p.Value.values.PSObject.Properties[$Op.name]
            if ($v) {
                $v.Value.kind = $kind
                $v.Value.value = $Op.value
            }
            else {
                $p.Value.values | Add-Member -MemberType NoteProperty -Name $Op.name -Value ([pscustomobject]@{ kind = $kind; value = $Op.value })
            }
            Save-MemoryStore -Path $MemStorePath -Store $MemStore
            return
        }
        if ($Op.type -eq 'service.startup') {
            $s = $MemStore.services.PSObject.Properties[$Op.name]
            if ($s) { $s.Value.startup = $Op.startupType }
            else { $MemStore.services | Add-Member -MemberType NoteProperty -Name $Op.name -Value ([pscustomobject]@{ startup = $Op.startupType }) }
            Save-MemoryStore -Path $MemStorePath -Store $MemStore
            return
        }
    }
    if ($Op.type -eq 'registry.set') {
        $kind = if ($Op.PSObject.Properties['valueType']) { $Op.valueType } else { 'DWord' }
        Set-RegistryValueTyped -PsPath $Op.path -Name $Op.name -Kind $kind -Value $Op.value
        return
    }
    if ($Op.type -eq 'service.startup') {
        Set-Service -Name $Op.name -StartupType $Op.startupType -ErrorAction Stop
        return
    }
    throw "П39: операция $($Op.type) не поддерживается"
}

function Undo-TweakOldState {
    # $Rec — строка op.begin журнала: старое состояние уже в ней (LIFO снаружи)
    param([object]$Rec, [string]$Backend, [object]$MemStore, [string]$MemStorePath)
    $old = $Rec.old
    if ($Rec.op -eq 'registry.set') {
        if ($Backend -eq 'memory') {
            $p = $MemStore.paths.PSObject.Properties[$Rec.path]
            if ($old.present) {
                if (-not $p) {
                    $MemStore.paths | Add-Member -MemberType NoteProperty -Name $Rec.path -Value ([pscustomobject]@{ existed = [bool]$old.pathExisted; values = [pscustomobject]@{} })
                    $p = $MemStore.paths.PSObject.Properties[$Rec.path]
                }
                $v = $p.Value.values.PSObject.Properties[$Rec.name]
                if ($v) {
                    $v.Value.kind = $old.kind
                    $v.Value.value = $old.value
                }
                else {
                    $p.Value.values | Add-Member -MemberType NoteProperty -Name $Rec.name -Value ([pscustomobject]@{ kind = $old.kind; value = $old.value })
                }
            }
            else {
                if ($p) { $p.Value.values.PSObject.Properties.Remove($Rec.name) }
            }
            if (-not $old.pathExisted -and $p) {
                # ключ создан твиком: снимаем, когда опустел; поднимаемся по пустым предкам
                $cur = $Rec.path
                while ($cur -and $MemStore.paths.PSObject.Properties[$cur]) {
                    $entry = $MemStore.paths.PSObject.Properties[$cur].Value
                    if ($entry.existed) { break }
                    if (@($entry.values.PSObject.Properties).Count -gt 0) { break }
                    $MemStore.paths.PSObject.Properties.Remove($cur)
                    $cur = Split-Path -Parent $cur
                }
            }
            Save-MemoryStore -Path $MemStorePath -Store $MemStore
            return
        }
        if ($old.present) {
            Set-RegistryValueTyped -PsPath $Rec.path -Name $Rec.name -Kind $old.kind -Value $old.value
        }
        else {
            Remove-RegistryValueTyped -PsPath $Rec.path -Name $Rec.name
            if (-not $old.pathExisted) {
                $cur = $Rec.path
                while ($cur -and ($cur -like 'HKCU:*' -or $cur -like 'HKLM:*')) {
                    $probe = ConvertTo-RegistrySubPath -PsPath $cur
                    if ([string]::IsNullOrEmpty($probe.sub)) { break }   # корень улья не трогаем
                    $key = $probe.hive.OpenSubKey($probe.sub)
                    if ($null -eq $key) { break }
                    $hasChildren = @($key.GetSubKeyNames()).Count -gt 0
                    $hasValues = @($key.GetValueNames()).Count -gt 0
                    $key.Close()
                    if ($hasChildren -or $hasValues) { break }
                    Remove-RegistryKeyIfEmpty -PsPath $cur
                    $cur = Split-Path -Parent $cur
                }
            }
        }
        return
    }
    if ($Rec.op -eq 'service.startup') {
        if ($old.present) {
            if ($Backend -eq 'memory') {
                $s = $MemStore.services.PSObject.Properties[$Rec.name]
                if ($s) { $s.Value.startup = $old.startup }
                else { $MemStore.services | Add-Member -MemberType NoteProperty -Name $Rec.name -Value ([pscustomobject]@{ startup = $old.startup }) }
                Save-MemoryStore -Path $MemStorePath -Store $MemStore
            }
            else {
                Set-Service -Name $Rec.name -StartupType $old.startup -ErrorAction Stop
            }
        }
        return
    }
    throw "П39: откат операции $($Rec.op) не поддерживается"
}

# ------------------------------------------------------------- проверки ----

function Test-ManifestShape {
    param([object]$Data)
    if (-not $Data.PSObject.Properties['id'] -or [string]::IsNullOrWhiteSpace("$($Data.id)")) {
        throw 'П39: в манифесте нет id'
    }
    if (-not $Data.PSObject.Properties['ops'] -or @($Data.ops).Count -eq 0) {
        throw 'П39: в манифесте пусто ops'
    }
    foreach ($op in $Data.ops) {
        if (-not ($script:SupportedOps -contains $op.type)) {
            throw "П39: операция '$($op.type)' вне whitelist исполнителя — fail-closed отказ до любой мутации"
        }
        if ($op.type -eq 'registry.set') {
            if (-not $op.path -or -not $op.name) { throw 'П39: registry.set без path/name' }
            $kind = if ($op.PSObject.Properties['valueType']) { $op.valueType } else { 'DWord' }
            if (-not ($script:RegistryKinds -contains $kind)) { throw "П39: valueType '$kind' не из списка $script:RegistryKinds" }
        }
        if ($op.type -eq 'service.startup') {
            if (-not $op.name -or -not $op.startupType) { throw 'П39: service.startup без name/startupType' }
            if (-not ($script:ServiceStartups -contains $op.startupType)) { throw "П39: startupType '$($op.startupType)' не из списка $script:ServiceStartups" }
        }
    }
}

# ------------------------------------------------------------------ ядро ----

function Invoke-DomovoyTweakJournal {
    <#
    .SYNOPSIS
        Применяет/откатывает твик по декларативному манифесту с undo-журналом.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$Manifest,
        [switch]$Undo,
        [switch]$Check,
        [switch]$Apply,
        [string]$FeatureId,
        [string]$JournalPath,
        [ValidateSet('registry', 'memory')]
        [string]$Backend = 'registry',
        [string]$MemoryStorePath
    )

    if (-not $JournalPath) {
        $base = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { [IO.Path]::GetTempPath() }
        $JournalPath = Join-Path $base 'Domovoy/tweaks/journal.jsonl'
    }

    # ---- режим -Check: форма манифеста, ноль мутаций
    if ($Check) {
        if (-not $Manifest) { throw 'П39: -Check требует -Manifest' }
        $data = Get-Content -LiteralPath $Manifest -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        Test-ManifestShape -Data $data
        return [pscustomobject]@{ Manifest = (Split-Path -Leaf $Manifest); Id = $data.id; Ops = @($data.ops).Count; Verdict = 'shape-ok' }
    }

    # ---- режим -Undo: обратный проход журнала (по умолчанию сухой прогон)
    if ($Undo) {
        $batch = Get-LastPendingBatch -Path $JournalPath -Id $FeatureId
        if (-not $batch) { throw "П39: в журнале $JournalPath нет неоткаченной партии (feature: $FeatureId)" }
        $rows = @(Read-Journal -Path $JournalPath | Where-Object { $_.batch -eq $batch -and $_.event -eq 'op.begin' })
        [array]::Reverse($rows)   # LIFO — обратный проход
        $plan = @()
        foreach ($r in $rows) {
            $restore = '<unset>'
            if ($r.old.present) { $restore = "$($r.old.kind): $($r.old.value)" }
            $plan += [pscustomobject]@{ op = $r.op; path = $r.path; name = $r.name; restore = $restore }
        }
        if (-not $Apply) {
            return [pscustomobject]@{ Mode = 'DryRun'; Batch = $batch; Ops = $plan }
        }
        $mem = $null
        if ($Backend -eq 'memory') {
            if (-not $MemoryStorePath) { throw 'П39: бэкенд memory требует -MemoryStorePath' }
            $mem = Get-MemoryStore -Path $MemoryStorePath
        }
        if ($PSCmdlet.ShouldProcess($batch, 'Откат твика по журналу (LIFO)')) {
            foreach ($r in $rows) {
                Undo-TweakOldState -Rec $r -Backend $Backend -MemStore $mem -MemStorePath $MemoryStorePath
            }
            Add-JournalEntry -Path $JournalPath -Entry @{ v = 1; event = 'batch.undone'; batch = $batch }
        }
        return [pscustomobject]@{ Mode = 'Undone'; Batch = $batch; Restored = @($rows).Count }
    }

    # ---- режим apply: применение манифеста с write-ahead журналом
    if (-not $Manifest) { throw 'П39: укажи -Manifest, либо -Undo, либо -Check' }
    $data = Get-Content -LiteralPath $Manifest -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    Test-ManifestShape -Data $data   # fail-closed ДО мутаций: whitelist + форма

    $pending = Get-LastPendingBatch -Path $JournalPath -Id $data.id
    if ($pending) {
        throw "П39: твик '$($data.id)' ещё не откачен (партия $pending) — откат обязателен перед новым применением"
    }

    $mem = $null
    if ($Backend -eq 'memory') {
        if (-not $MemoryStorePath) { throw 'П39: бэкенд memory требует -MemoryStorePath' }
        $mem = Get-MemoryStore -Path $MemoryStorePath
    }

    $batch = [guid]::NewGuid().ToString('N')
    $applied = 0
    foreach ($op in $data.ops) {
        $old = Get-TweakOldState -Op $op -Backend $Backend -MemStore $mem
        # дрейф-страж: заявленное в манифесте «старое» обязано совпасть с миром
        if ($op.PSObject.Properties['old'] -and $null -ne $op.old) {
            $actual = if ($op.type -eq 'registry.set') { $old.value } else { $old.startup }
            if ($old.present -and "$actual" -ne "$($op.old)") {
                throw "П39: дрейф мира — манифест $($data.id) обещает old='$($op.old)', а на месте '$actual'; домовой не лжёт"
            }
        }
        $target = "$($op.type) $($op.path)$($op.name)"
        if (-not $PSCmdlet.ShouldProcess($target, 'Применить новое значение')) { continue }
        $rec = @{
            v = 1; event = 'op.begin'; batch = $batch; feature = "$($data.id)"
            op = "$($op.type)"
        }
        if ($op.type -eq 'registry.set') {
            $rec.path = "$($op.path)"; $rec.name = "$($op.name)"
            $rec.old = @{ present = [bool]$old.present; kind = $old.kind; value = $old.value; pathExisted = [bool]$old.pathExisted }
        }
        else {
            $rec.path = ''; $rec.name = "$($op.name)"
            $rec.old = @{ present = [bool]$old.present; startup = $old.startup }
        }
        Add-JournalEntry -Path $JournalPath -Entry $rec   # УПРЕЖДАЮЩАЯ запись — гарантия отката
        Set-TweakNewState -Op $op -Backend $Backend -MemStore $mem -MemStorePath $MemoryStorePath
        Add-JournalEntry -Path $JournalPath -Entry @{ v = 1; event = 'op.applied'; batch = $batch; op = "$($op.type)" }
        $applied++
    }
    Add-JournalEntry -Path $JournalPath -Entry @{ v = 1; event = 'batch.done'; batch = $batch; feature = "$($data.id)" }
    return [pscustomobject]@{ Mode = 'Applied'; Batch = $batch; Feature = $data.id; Ops = $applied; Journal = $JournalPath }
}

# ------------------------------------------------------------------ вход ----

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-DomovoyTweakJournal @PSBoundParameters
}
