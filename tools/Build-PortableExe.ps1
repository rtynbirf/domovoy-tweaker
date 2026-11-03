<#
.SYNOPSIS
    Сборка однофайлового портативного лаунчера Domovoy-<версия>-Portable.exe.

.DESCRIPTION
    Один шаг - один артефакт: весь релизный payload (модуль Domovoy,
    каталог манифестов config/, схемы schema/, CLI-шимы domovoy.ps1 и
    domovoy.exe, README, LICENSE) упаковывается в zip и встраивается
    управляемым ресурсом в DomovoyPortable.cs. Компиляция - машинным
    csc.exe .NET Framework (тот же, что собирает и winget-шим), C#5.

    Гейты по ходу сборки:
      1. staging: восемь обязательных путей payload;
      2. компиляция: код выхода csc;
      3. selftest: --selftest собираемого exe (распаковка во временный
         каталог + проверка обязательных файлов + сверка версии манифеста
         с версией payload);
      4. контрольная сумма - ассет .sha256 в формате sha256sum
         (сумма + два пробела + имя).

    Используется release-джобом portable-exe (CI) и доступна локально:
    без -ShimExe шим компилируется сам из packaging/shim/DomovoyShim.cs.

.PARAMETER RepoDir
    Корень рабочего дерева репозитория (обязательный).

.PARAMETER OutputDir
    Каталог результатов. По умолчанию - %TEMP%\domovoy-portable-<версия>.
    Финальные артефакты ложатся в корень OutputDir, технические файлы
    (stage, payload) - в подкаталог _build.

.PARAMETER ShimExe
    Путь к уже собранному domovoy.exe (в CI - артефакт джоба shim-exe,
    правило "один файл везде"). Если не задан - шим компилируется на месте.

.PARAMETER CscPath
    Путь к csc.exe. По умолчанию - %WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe.

.EXAMPLE
    tools/Build-PortableExe.ps1 -RepoDir .

.EXAMPLE
    tools/Build-PortableExe.ps1 -RepoDir . -ShimExe shim-artifact/domovoy.exe -OutputDir portable-artifact
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RepoDir,

    [string]$OutputDir,

    [string]$ShimExe,

    [string]$CscPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- 1. Входные точки -------------------------------------------------------

$RepoDir = (Resolve-Path -LiteralPath $RepoDir).Path
$manifestPath = Join-Path $RepoDir 'src/Domovoy/Domovoy.psd1'
$launcherSource = Join-Path $RepoDir 'packaging/shim/DomovoyPortable.cs'
$shimSource = Join-Path $RepoDir 'packaging/shim/DomovoyShim.cs'
foreach ($file in @($manifestPath, $launcherSource, $shimSource)) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        throw "Required source not found: $file"
    }
}

$versionLine = Select-String -LiteralPath $manifestPath -Pattern "ModuleVersion\s*=\s*'([^']+)'"
if (-not $versionLine) { throw "ModuleVersion not found in $manifestPath" }
$version = $versionLine.Matches[0].Groups[1].Value
Write-Host "Portable build for Domovoy $version"

# v1.6.0 gates: the exe must carry the product identity (icon + VERSIONINFO),
# and the AssemblyInfo version can never drift away from the manifest version.
$assemblyInfoPath = Join-Path $RepoDir 'packaging/shim/AssemblyInfo.cs'
$iconPath = Join-Path $RepoDir 'src/Domovoy/domovoy.ico'
foreach ($file in @($assemblyInfoPath, $iconPath)) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        throw "Required product-identity file not found: $file"
    }
}
$assemblyVersionLine = Select-String -LiteralPath $assemblyInfoPath -Pattern 'AssemblyInformationalVersion\("([^"]+)"\)'
if (-not $assemblyVersionLine) { throw "AssemblyInformationalVersion not found in $assemblyInfoPath" }
$assemblyVersion = $assemblyVersionLine.Matches[0].Groups[1].Value
if ($assemblyVersion -ne $version) {
    throw "Version drift: manifest ModuleVersion '$version' != AssemblyInfo '$assemblyVersion' (update both together)"
}

if (-not $OutputDir) { $OutputDir = Join-Path $env:TEMP "domovoy-portable-$version" }
$OutputDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDir)
$buildDir = Join-Path $OutputDir '_build'
Remove-Item -LiteralPath $OutputDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $buildDir -Force | Out-Null
Write-Host "Output directory: $OutputDir"

if (-not $CscPath) {
    $CscPath = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
}
if (-not (Test-Path -LiteralPath $CscPath -PathType Leaf)) {
    throw "csc.exe not found at $CscPath (this builder targets the .NET Framework in-box compiler)"
}

# --- 2. Staging payload по раскладке релизного zip --------------------------

$stage = Join-Path $buildDir 'stage'
$stageModule = Join-Path $stage 'Domovoy'
New-Item -ItemType Directory -Path $stageModule -Force | Out-Null
Copy-Item -Path (Join-Path $RepoDir 'src/Domovoy/*') -Destination $stageModule -Recurse
Copy-Item -Path (Join-Path $RepoDir 'config'), (Join-Path $RepoDir 'schema') -Destination "$stageModule/" -Recurse
Copy-Item -Path (Join-Path $RepoDir 'packaging/shim/domovoy.ps1') -Destination $stageModule
Copy-Item -Path (Join-Path $RepoDir 'README.md'), (Join-Path $RepoDir 'LICENSE') -Destination $stage

# Шим: готовый файл (правило "один файл везде") либо сборка на месте.
$shimTarget = Join-Path $stageModule 'domovoy.exe'
if ($ShimExe) {
    $ShimExe = (Resolve-Path -LiteralPath $ShimExe).Path
    Copy-Item -LiteralPath $ShimExe -Destination $shimTarget -Force
    Write-Host "Shim taken from: $ShimExe"
}
else {
    & $CscPath /nologo /target:exe /out:"$shimTarget" "$shimSource"
    if ($LASTEXITCODE -ne 0) { throw "csc failed compiling the shim (exit code $LASTEXITCODE)" }
    Write-Host 'Shim compiled on the spot (no -ShimExe given).'
}

$required = @(
    'Domovoy/Domovoy.psd1',
    'Domovoy/Domovoy.psm1',
    'Domovoy/domovoy.ps1',
    'Domovoy/domovoy.exe',
    'Domovoy/domovoy.ico',
    'Domovoy/config',
    'Domovoy/schema',
    'README.md',
    'LICENSE'
)
foreach ($rel in $required) {
    $p = Join-Path $stage $rel
    if (-not (Test-Path -LiteralPath $p)) { throw "Staging bug: $rel is missing from the payload stage" }
    # Directories have no Length property - guard files only (strict mode
    # makes a bare .Length on DirectoryInfo a hard error, caught live by
    # release run 18).
    $item = Get-Item -LiteralPath $p
    if (-not $item.PSIsContainer -and $item.Length -eq 0) { throw "Staging bug: $rel is empty" }
}
Write-Host ("Staging OK: {0} required paths present" -f $required.Count)

# --- 3. Payload zip + версия, оба с контрактными именами ресурсов -----------

$payloadZip = Join-Path $buildDir 'Domovoy.Portable.payload.zip'
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $payloadZip -Force

$payloadVersion = Join-Path $buildDir 'Domovoy.Portable.payload.version'
Set-Content -LiteralPath $payloadVersion -Value $version -NoNewline -Encoding Ascii

$payloadSha = (Get-FileHash -LiteralPath $payloadZip -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Host "Payload zip: $payloadZip (sha256 $payloadSha)"

# --- 4. Компиляция лаунчера (C#5, машинный csc) ------------------------------

$launcherCopy = Join-Path $buildDir 'DomovoyPortable.cs'
Copy-Item -LiteralPath $launcherSource -Destination $launcherCopy
$exePath = Join-Path $OutputDir "Domovoy-$version-Portable.exe"

& $CscPath `
    /nologo `
    /target:exe `
    /platform:anycpu `
    /optimize+ `
    /langversion:5 `
    /win32manifest:"$(Join-Path $RepoDir 'packaging/shim/DomovoyPortable.manifest')" `
    /win32icon:"$iconPath" `
    /out:"$exePath" `
    /r:System.IO.Compression.dll `
    /r:System.IO.Compression.FileSystem.dll `
    /res:"$payloadZip,Domovoy.Portable.payload.zip" `
    /res:"$payloadVersion,Domovoy.Portable.payload.version" `
    "$launcherCopy" "$assemblyInfoPath"
if ($LASTEXITCODE -ne 0) { throw "csc failed compiling the portable launcher (exit code $LASTEXITCODE)" }
if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) { throw 'csc produced no portable executable' }
Write-Host "Compiled: $exePath"

# --- 5. Гейт: selftest собираемого exe ---------------------------------------

& $exePath --selftest
if ($LASTEXITCODE -ne 0) { throw "Portable selftest failed with exit code $LASTEXITCODE" }

# --- 6. Контрольная сумма (формат sha256sum) ---------------------------------

$exeSha = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash.ToLowerInvariant()
$exeName = Split-Path -Leaf $exePath
$shaPath = Join-Path $OutputDir "$exeName.sha256"
Set-Content -LiteralPath $shaPath -Value "$exeSha  $exeName" -Encoding Ascii

Write-Host ''
Write-Host "Portable exe : $exePath"
Write-Host "SHA-256      : $exeSha"
Write-Host "Checksum file: $shaPath"
