#Requires -Version 5.1
<#
.SYNOPSIS
    Локальный one-click прогон ДОМОВОЙ: зеркало CI + локальная сборка артефакта.

.DESCRIPTION
    Запускается двойным кликом через DOMOVOY-ONECLICK.bat (или вручную).
    Повторяет контур CI (.github/workflows/ci.yml, job "Lint + Test"):
      1. Синхронизация локальной копии (fetch + pull --ff-only, без force).
      2. Модули: PSScriptAnalyzer + Pester РОВНО 5.7.1 (как в CI).
      3. PSScriptAnalyzer по src с настройками репо, гейт Error.
      4. Pester: на pwsh 7 - полный tests, на Windows PowerShell 5.1 -
         те же 5.1-безопасные сьюты, что в CI-ноге 5.1 (Loop + Module).
      5. JSON-схемы манифестов/профилей/групп (на 5.1 честно пропускается:
         в CI этот шаг исполняется на pwsh 7).
      6. Верификация упаковки: свежий stage, нейтральный каталог,
         Get-DomovoyFeature на "установленной" копии (гейт P0-1).
      7. Локальная сборка Domovoy-<версия>.zip + .sha256 по раскладке
         release.yml (включая exe-шим через csc.exe, если найден).
    Все артефакты и логи кладутся ВНЕ репозитория:
      %LOCALAPPDATA%\Domovoy\artifacts и %LOCALAPPDATA%\Domovoy\logs.
    Код выхода = число упавших шагов (0 = всё зелёное).

.NOTES
    Прав администратора не требует: тесты и верификация работают на
    временных ключах/каталогах; ничего в системе не меняется.
#>

[CmdletBinding()]
param(
    # Каталог локальной копии репозитория (создаётся батником при первом запуске).
    [string]$RepoDir = (Join-Path $HOME 'domovoy-tweaker'),
    # Путь к git.exe (батник подставляет найденный).
    [string]$GitExe = 'git'
)

$ErrorActionPreference = 'Stop'
$Major = $PSVersionTable.PSVersion.Major
$On51 = ($Major -le 5)
$OutDir = Join-Path $env:LOCALAPPDATA 'Domovoy\artifacts'
$LogDir = Join-Path $env:LOCALAPPDATA 'Domovoy\logs'
foreach ($d in @($OutDir, $LogDir)) {
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}
$Stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$LogPath = Join-Path $LogDir ("domovoy-localci-{0}.log" -f $Stamp)

$script:Steps = New-Object System.Collections.Generic.List[object]
$script:FailedSteps = 0

function Write-Rule {
    param([string]$Title)
    Write-Host ''
    Write-Host ('=' * 66) -ForegroundColor DarkCyan
    Write-Host ('  ' + $Title) -ForegroundColor Cyan
    Write-Host ('=' * 66) -ForegroundColor DarkCyan
}

function Set-StepResult {
    param([string]$Name, [bool]$Ok, [string]$Detail)
    $status = 'FAIL'
    if ($Ok) { $status = 'OK' } else { $script:FailedSteps = $script:FailedSteps + 1 }
    $color = 'Red'
    if ($Ok) { $color = 'Green' }
    Write-Host ('  [' + $status + '] ' + $Name) -ForegroundColor $color
    if ($Detail) { Write-Host ('         ' + $Detail) -ForegroundColor Gray }
    $script:Steps.Add([pscustomobject]@{ Step = $Name; Status = $status; Detail = $Detail }) | Out-Null
}

function Invoke-Git {
    # git молча: без брошенных ошибок от stderr, с честным кодом выхода.
    param([string[]]$GitArgs)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & $GitExe @GitArgs 2>&1
        $text = @($out | ForEach-Object { $_.ToString() })
        return @{ ExitCode = $LASTEXITCODE; Output = $text }
    }
    finally { $ErrorActionPreference = $prev }
}

function Get-LatestTag {
    $r = Invoke-Git @('describe', '--tags', '--abbrev=0')
    if ($r.ExitCode -eq 0 -and $r.Output.Count -gt 0) { return ([string]$r.Output[0]) }
    return $null
}

Write-Host ''
Write-Host ('=' * 66) -ForegroundColor DarkCyan
Write-Host '  ДОМОВОЙ - локальный one-click прогон (зеркало CI + сборка)' -ForegroundColor Cyan
Write-Host ('  Репозиторий : ' + $RepoDir) -ForegroundColor Cyan
Write-Host ('  Движок      : PowerShell ' + $PSVersionTable.PSVersion.ToString()) -ForegroundColor Cyan
Write-Host ('  Лог         : ' + $LogPath) -ForegroundColor Cyan
Write-Host ('=' * 66) -ForegroundColor DarkCyan

try { Start-Transcript -LiteralPath $LogPath | Out-Null } catch { }

try {
    # ---------------------------------------------------------------
    if (-not (Test-Path -LiteralPath (Join-Path $RepoDir 'src\Domovoy\Domovoy.psd1'))) {
        throw ("В '{0}' нет локальной копии репозитория ДОМОВОЙ. Запустите DOMOVOY-ONECLICK.bat - он сам склонирует репозиторий." -f $RepoDir)
    }

    # ======================= ШАГ 1: синхронизация ==================
    Write-Rule 'ШАГ 1/7: синхронизация локальной копии'
    $syncDetail = ''
    $fetch = Invoke-Git @('-C', $RepoDir, 'fetch', '--quiet', 'origin')
    if ($fetch.ExitCode -ne 0) { $syncDetail = 'fetch не удался (сеть?) - '; }

    $dirty = Invoke-Git @('-C', $RepoDir, 'status', '--porcelain')
    if ($dirty.Output.Count -gt 0) {
        $syncDetail = $syncDetail + 'локальные изменения обнаружены - pull пропущен (ничего не трогаем)'
    }
    else {
        $pull = Invoke-Git @('-C', $RepoDir, 'pull', '--ff-only', '--quiet', 'origin', 'main')
        if ($pull.ExitCode -ne 0) { $syncDetail = $syncDetail + 'pull --ff-only не удался - работаем на локальной копии' }
    }
    $head = Invoke-Git @('-C', $RepoDir, 'rev-parse', '--short', 'HEAD')
    $headSha = '?'
    if ($head.ExitCode -eq 0 -and $head.Output.Count -gt 0) { $headSha = [string]$head.Output[0] }
    $tag = Get-LatestTag
    $syncDetail = ('HEAD {0}, последний тег {1}. {2}' -f $headSha, $tag, $syncDetail).TrimEnd()
    Set-StepResult 'Синхронизация репозитория' $true $syncDetail

    # ======================= ШАГ 2: модули =========================
    Write-Rule 'ШАГ 2/7: модули (PSScriptAnalyzer + Pester 5.7.1, как в CI)'
    $modDetail = @()
    if ($On51) {
        # Классика 5.1: без NuGet-провайдера и TLS 1.2 галерея молчит.
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Scope CurrentUser -Force | Out-Null
        } catch { $modDetail += ('NuGet-провайдер: ' + $_.Exception.Message) }
    }
    try { Set-PSRepository -Name PSGallery -InstallationPolicy Trusted } catch { $modDetail += ('PSGallery: ' + $_.Exception.Message) }

    $moduleWants = @(
        @{ Name = 'PSScriptAnalyzer'; Args = @('-Name', 'PSScriptAnalyzer', '-Scope', 'CurrentUser', '-Force') },
        @{ Name = 'Pester'; Args = @('-Name', 'Pester', '-RequiredVersion', '5.7.1', '-Scope', 'CurrentUser', '-Force', '-SkipPublisherCheck') }
    )
    foreach ($m in $moduleWants) {
        try { Install-Module @($m.Args) -ErrorAction Stop }
        catch {
            $present = Get-Module -ListAvailable -Name $m.Name | Sort-Object Version -Descending | Select-Object -First 1
            if ($null -eq $present) { throw ("Не удалось установить модуль {0}: {1}" -f $m.Name, $_.Exception.Message) }
            $modDetail += ('{0}: установка не удалась, работаем на локальном {1}' -f $m.Name, $present.Version)
        }
    }
    Import-Module -Name PSScriptAnalyzer -ErrorAction SilentlyContinue
    Import-Module -Name Pester -RequiredVersion 5.7.1
    $pesterModVersion = (Get-Module Pester).Version.ToString()
    $analyzerVersion = '-'
    $analyzerModule = Get-Module PSScriptAnalyzer
    if ($null -ne $analyzerModule) { $analyzerVersion = $analyzerModule.Version.ToString() }
    $modDetail += ('Pester {0}, PSScriptAnalyzer {1}' -f $pesterModVersion, $analyzerVersion)
    Set-StepResult 'Модули установлены и импортированы' $true ($modDetail -join '; ')

    # ======================= ШАГ 3: анализатор =====================
    Write-Rule 'ШАГ 3/7: PSScriptAnalyzer (гейт Error, настройки репо)'
    $anResults = Invoke-ScriptAnalyzer -Path (Join-Path $RepoDir 'src') -Recurse -Settings (Join-Path $RepoDir 'PSScriptAnalyzerSettings.psd1')
    foreach ($r in $anResults) {
        Write-Host ('         {0} {1}:{2} {3}' -f $r.Severity, $r.ScriptName, $r.Line, $r.Message) -ForegroundColor Gray
    }
    $anErrors = @($anResults | Where-Object { $_.Severity -eq 'Error' })
    Set-StepResult 'Анализатор' ($anErrors.Count -eq 0) ('ошибок: {0}, всего сообщений: {1}' -f $anErrors.Count, @($anResults).Count)

    # ======================= ШАГ 4: Pester =========================
    Write-Rule 'ШАГ 4/7: Pester 5.7.1 (то же, что в CI)'
    $cfg = New-PesterConfiguration
    if ($On51) {
        # Зеркало CI-ноги "PS 5.1 leg": только 5.1-безопасные сьюты.
        $cfg.Run.Path = @('tests/Domovoy.Loop.Tests.ps1', 'tests/Domovoy.Module.Tests.ps1')
        $cfg.CodeCoverage.Enabled = $false
    }
    else {
        $cfg.Run.Path = 'tests'
        $cfg.CodeCoverage.Enabled = $true
        $cfg.CodeCoverage.Path = (Join-Path $RepoDir 'src/Domovoy/**/*.ps1')
    }
    $cfg.Run.Exit = $false
    $cfg.Output.Verbosity = 'Detailed'
    $cfg.TestResult.Enabled = $true
    $cfg.TestResult.OutputPath = (Join-Path $OutDir 'testResults.xml')
    $cfg.Run.PassThru = $true
    $pesterOk = $false
    $pesterDetail = ''
    Push-Location $RepoDir
    try {
        $result = Invoke-Pester -Configuration $cfg
        foreach ($t in @($result.Failed)) {
            foreach ($e in @($t.ErrorRecord)) {
                $msg = ($e.Exception.Message -replace "`r?`n", ' ')
                Write-Host ('         FAILED: {0} :: {1}' -f $t.Path, $msg) -ForegroundColor Red
            }
        }
        $cc = $result.CodeCoverage
        $analyzed = [int]$cc.CommandsAnalyzedCount
        $executed = [int]$cc.CommandsExecutedCount
        $covText = 'покрытие не собиралось (5.1-нога)'
        if ($analyzed -gt 0) {
            $pct = [math]::Round((100.0 * $executed / $analyzed), 1)
            $covText = ('покрытие {0}% (команды {1}/{2})' -f $pct.ToString('0.0', [System.Globalization.CultureInfo]::InvariantCulture), $executed, $analyzed)
        }
        $badContainers = @($result.Containers | Where-Object { $_.Status -eq 'Failed' })
        $pesterOk = (($result.FailedCount -eq 0) -and ($badContainers.Count -eq 0))
        $pesterDetail = ('пройдено {0}, упало {1}, контейнеров упало {2}; {3}; NUnit: {4}' -f
            $result.PassedCount, $result.FailedCount, $badContainers.Count, $covText, $cfg.TestResult.OutputPath)
    }
    finally { Pop-Location }
    Set-StepResult 'Pester' $pesterOk $pesterDetail

    # ======================= ШАГ 5: JSON-схемы =====================
    Write-Rule 'ШАГ 5/7: JSON-схемы (манифесты, профили, группы)'
    if ($On51) {
        Set-StepResult 'JSON-схемы' $true 'пропущено на Windows PowerShell 5.1 (в CI этот шаг исполняется на pwsh 7)'
    }
    else {
        $jsonFail = 0
        $jsonCount = 0
        $schemaMap = @(
            @{ Dir = 'config/features'; Schema = 'schema/features.schema.json' },
            @{ Dir = 'config/profiles'; Schema = 'schema/profiles.schema.json' },
            @{ Dir = 'config/groups'; Schema = 'schema/groups.schema.json' }
        )
        foreach ($pair in $schemaMap) {
            $schemaPath = Join-Path $RepoDir $pair.Schema
            Get-ChildItem -LiteralPath (Join-Path $RepoDir $pair.Dir) -Filter '*.json' | ForEach-Object {
                $jsonCount = $jsonCount + 1
                try {
                    Test-Json -Json (Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8) -SchemaFile $schemaPath -ErrorAction Stop | Out-Null
                }
                catch {
                    $jsonFail = $jsonFail + 1
                    Write-Host ('         SCHEMA FAIL: {0} :: {1}' -f $_.Name, $_.Exception.Message) -ForegroundColor Red
                }
            }
        }
        Set-StepResult 'JSON-схемы' ($jsonFail -eq 0) ('проверено файлов: {0}, ошибок: {1}' -f $jsonCount, $jsonFail)
    }

    # ============ ШАГ 6: верификация упаковки (гейт P0-1) ==========
    Write-Rule 'ШАГ 6/7: верификация упаковки (каталог едет внутри артефакта)'
    $stage = Join-Path ([System.IO.Path]::GetTempPath()) ('domovoy-packcheck-' + [guid]::NewGuid().ToString('N'))
    $packOk = $false
    $packDetail = ''
    try {
        New-Item -ItemType Directory -Path (Join-Path $stage 'Domovoy') -Force | Out-Null
        Copy-Item -Path (Join-Path $RepoDir 'src/Domovoy/*') -Destination (Join-Path $stage 'Domovoy') -Recurse -Force
        Copy-Item -Path (Join-Path $RepoDir 'config'), (Join-Path $RepoDir 'schema') -Destination (Join-Path $stage 'Domovoy/') -Recurse -Force
        Copy-Item -Path (Join-Path $RepoDir 'README.md'), (Join-Path $RepoDir 'LICENSE') -Destination $stage -Force

        # Как в CI: без DOMOVOY_FEATURES_DIR и из нейтрального каталога,
        # чтобы чекаут репозитория не мог подстраховать резолвер.
        Remove-Item Env:DOMOVOY_FEATURES_DIR -ErrorAction SilentlyContinue
        Push-Location ([System.IO.Path]::GetTempPath())
        try {
            Remove-Module -Name Domovoy -ErrorAction SilentlyContinue
            Import-Module -Name (Join-Path $stage 'Domovoy/Domovoy.psd1') -Force
            $features = @(Get-DomovoyFeature)
            $profiles = @(Get-DomovoyProfile)
            $groups = @(Get-DomovoyGroup)
            $packDetail = ('в артефакте: функций {0}, профилей {1}, групп {2}' -f $features.Count, $profiles.Count, $groups.Count)
            $packOk = ($features.Count -ge 56) -and ($profiles.Count -ge 2) -and ($groups.Count -ge 2)
            $dups = @($features | Group-Object -Property Id | Where-Object { $_.Count -gt 1 })
            if ($dups.Count -gt 0) {
                $packOk = $false
                $packDetail = $packDetail + ('; дубликаты id: {0}' -f (($dups | ForEach-Object { $_.Name }) -join ', '))
            }
            if (-not $packOk) { $packDetail = 'ГАТЕТ УПАКОВКИ: ' + $packDetail }
        }
        finally { Pop-Location }
    }
    catch {
        $packOk = $false
        $packDetail = 'ошибка упаковки: ' + $_.Exception.Message
    }
    finally { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
    Set-StepResult 'Верификация упаковки' $packOk $packDetail

    # ============ ШАГ 7: локальная сборка zip + sha256 =============
    Write-Rule 'ШАГ 7/7: локальная сборка Domovoy-<версия>.zip + .sha256'
    $version = 'local'
    if ($tag -like 'v*') { $version = $tag.Substring(1) }
    $zipPath = Join-Path $OutDir ('Domovoy-{0}.zip' -f $version)
    $buildOk = $false
    $buildDetail = ''
    $stage2 = Join-Path ([System.IO.Path]::GetTempPath()) ('domovoy-stage-' + [guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Path (Join-Path $stage2 'Domovoy') -Force | Out-Null
        Copy-Item -Path (Join-Path $RepoDir 'src/Domovoy/*') -Destination (Join-Path $stage2 'Domovoy') -Recurse -Force
        Copy-Item -Path (Join-Path $RepoDir 'config'), (Join-Path $RepoDir 'schema') -Destination (Join-Path $stage2 'Domovoy/') -Recurse -Force
        Copy-Item -Path (Join-Path $RepoDir 'README.md'), (Join-Path $RepoDir 'LICENSE') -Destination $stage2 -Force
        Copy-Item -Path (Join-Path $RepoDir 'packaging/shim/domovoy.ps1') -Destination (Join-Path $stage2 'Domovoy/domovoy.ps1') -Force
        Copy-Item -Path (Join-Path $RepoDir 'packaging/shim/DomovoyShim.cs') -Destination (Join-Path $stage2 'Domovoy/DomovoyShim.cs') -Force

        # exe-шим: как release-джоб shim-exe - штатный csc.exe .NET Framework.
        $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
        if (-not (Test-Path -LiteralPath $csc)) { $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
        if (Test-Path -LiteralPath $csc) {
            & $csc /nologo /target:exe /out:(Join-Path $stage2 'Domovoy/domovoy.exe') (Join-Path $stage2 'Domovoy/DomovoyShim.cs') | Out-Null
            if (Test-Path -LiteralPath (Join-Path $stage2 'Domovoy/domovoy.exe')) {
                $buildDetail = 'exe-шим собран csc.exe; '
            }
            else { $buildDetail = 'exe-шим: csc не выдал файл - zip без него; ' }
        }
        else { $buildDetail = 'exe-шим не собран (csc.exe не найден) - zip без него; ' }

        if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
        Compress-Archive -Path (Join-Path $stage2 '*') -DestinationPath $zipPath -Force
        $zipFile = Get-Item -LiteralPath $zipPath
        $sha = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
        # Формат sha256sum: два пробела между суммой и именем (как в релизе).
        $shaLine = ('{0}  Domovoy-{1}.zip' -f $sha, $version)
        Set-Content -LiteralPath (Join-Path $OutDir ('Domovoy-{0}.zip.sha256' -f $version)) -Value $shaLine -Encoding ASCII
        $buildOk = ($zipFile.Length -gt 0)
        $buildDetail = $buildDetail + ('{0} ({1} КБ); sha256 {2}...' -f $zipPath, [math]::Round($zipFile.Length / 1KB), $sha.Substring(0, 12))
    }
    catch {
        $buildOk = $false
        $buildDetail = 'ошибка сборки: ' + $_.Exception.Message
    }
    finally { Remove-Item -LiteralPath $stage2 -Recurse -Force -ErrorAction SilentlyContinue }
    Set-StepResult 'Сборка артефакта' $buildOk $buildDetail

    # ------------------------- ИТОГ --------------------------------
    Write-Rule 'ИТОГ'
    foreach ($s in $script:Steps) {
        $color = 'Red'
        if ($s.Status -eq 'OK') { $color = 'Green' }
        Write-Host ('  [{0}] {1}' -f $s.Status, $s.Step) -ForegroundColor $color
        if ($s.Detail) { Write-Host ('         ' + $s.Detail) -ForegroundColor Gray }
    }
    Write-Host ''
    Write-Host ('  Артефакты : ' + $OutDir) -ForegroundColor Cyan
    Write-Host ('  Лог       : ' + $LogPath) -ForegroundColor Cyan
    Write-Host ('  Результат : {0} из {1} шагов зелёные' -f ($script:Steps.Count - $script:FailedSteps), $script:Steps.Count) -ForegroundColor Cyan
    if ($script:FailedSteps -gt 0) {
        Write-Host '  ВЕРДИКТ: КРАСНОЕ - см. детали шагов выше.' -ForegroundColor Red
    }
    else {
        Write-Host '  ВЕРДИКТ: ВСЁ ЗЕЛЁНОЕ - репозиторий в рабочем состоянии.' -ForegroundColor Green
    }
    Write-Host ''
}
catch {
    Set-StepResult 'Необработанная ошибка' $false $_.Exception.Message
    Write-Host ('  КРИТИЧЕСКАЯ ОШИБКА: {0}' -f $_.Exception.Message) -ForegroundColor Red
}
finally {
    try { Stop-Transcript | Out-Null } catch { }
}

if ($script:FailedSteps -gt 0) { exit $script:FailedSteps }
exit 0
