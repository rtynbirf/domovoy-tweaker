# Дистрибуция ДОМОВОГО

Как модуль доезжает до пользователя, что здесь честно сделано, а что —
заготовлено под ключ владельца.

## Установка пользователем

### PowerShell Gallery (основной путь, одна команда)

```powershell
Install-Module -Name Domovoy -Scope CurrentUser
Import-Module Domovoy
```

Галерейный пакет несёт то же, что и zip: каталог манифестов `config/` и
схемы лежат внутри модуля — `Get-DomovoyFeature` видит функции сразу после
установки.

Критерий приёмки вехи v0.6.0: установка одной командой из PSGallery;
`install.ps1` не нужен — его не существует.

### Из zip-архива релиза

Каждый релиз на GitHub вкладывает `Domovoy-<версия>.zip` (модуль + каталог
манифестов `config/` + схемы `schema/` + README + LICENSE + CLI-шимы
`Domovoy/domovoy.ps1` и `Domovoy/domovoy.exe`). Распаковать и импортировать —
каталог функций работает сразу, без git-клона:

```powershell
Import-Module .\Domovoy\Domovoy.psd1 -Force
```

### Портативный EXE (один файл, без установки)

С v1.5.3 релиз вкладывает `Domovoy-<версия>-Portable.exe`: весь пакет
(модуль, каталог, схемы, оба CLI-шима, README, LICENSE) встроен в один exe.
Двойной клик — распаковка в `Domovoy-<версия>\` рядом с exe (или в
`%LOCALAPPDATA%\Domovoy\app`, если каталог только для чтения) и запуск GUI
(`Show-Domovoy`); аргументы командной строки форвардятся CLI-шиму дословно;
`--selftest` — машинная проверка упаковки, `--extract [каталог]` —
распаковка без запуска. Исходник — `packaging/shim/DomovoyPortable.cs`
С v1.6.0 двойной клик не показывает ни одного окна консоли: лаунчер
стартует GUI отсоединённо и завершается; фатальные ошибки старта
показываются диалогом с журналом `%LOCALAPPDATA%\Domovoy\logs`
(аргументы CLI и `--wait` работают по-прежнему, с видимой консолью).
exe несёт иконку и VERSIONINFO 1.6.0.0 (название/издатель/версия);
`--selftest` дополнительно сверяет версию сборки с версией payload.
Эргономическая ревизия канала — `docs/analysis/release-practices-audit.md`.
(C#5, машинный `csc.exe` на CI), сборщик — `tools/Build-PortableExe.ps1`;
exe не подписан (сертификат — v1.6 п.4), SmartScreen предупредит об
«неизвестном издателе» — это ожидаемо для неподписанного открытого кода.

## Что делает release-конвейер при теге `v*`

1. **Заметки релиза** — секция CHANGELOG `[x.y.z]` вырезается автоматически
   (тот же awk-конвейер, что и в v0.3.0+).
2. **Zip-артефакт** — `Domovoy-<версия>.zip`, sha256 считается, попадает в
   winget-манифест и с v1.4.0 вкладывается в релиз отдельным ассетом
   `Domovoy-<версия>.zip.sha256` (формат sha256sum: сумма + два пробела + имя
   файла).
3. **Winget-манифесты** — `packaging/winget/generate.py` собирает из шаблонов
   три YAML (version / installer / defaultLocale) в `winget-manifests/` и
   вкладывает их в релиз как `Domovoy-<версия>-winget-manifests.zip`.
4. **Портативный exe (v1.5.3)** — джоб `portable-exe` (windows-latest):
   `tools/Build-PortableExe.ps1` собирает однофайловый лаунчер
   `Domovoy-<версия>-Portable.exe` (payload встроен ресурсом, шим берётся из
   артефакта `shim-exe` — правило «один файл везде»), гейтит его
   `--selftest`-ом и сквозным прогоном `Get-DomovoyLanguage` через exe;
   release-джоб вкладывает exe и его `.sha256` в релиз наравне с zip.
5. **Подпись кода (опционально)** — job `sign`: если в секретах репозитория
   заданы `CODE_SIGNING_PFX` (base64 от .pfx) и `CODE_SIGNING_PASSWORD`,
   все `*.ps1/*.psm1/*.psd1` подписываются Authenticode (SHA256, сервер
   меток времени digicert), и в релиз докладывается
   `Domovoy-<версия>-signed.zip`. Без сертификата модуль выходит
   неподписанным **по задумке** — job честно пишет об этом и не падает.
6. **PSGallery (опционально)** — job `publish-psgallery`: если задан секрет
   `PSGALLERY_API_KEY`, модуль публикуется через `Publish-PSResource`
   (PSResourceGet; v1.6 п.1 — устаревший `Publish-Module` заменён в v1.4.1).
   Каталог и схемы уже внутри пакета — P0-1 закрыт. Гейт v1.5: релиз
   стартует только после зелёного CI-прогона ровно тегированного коммита
   (job `await-tests`), а пустая секция CHANGELOG валит релиз вместо
   публикации заглушки. Ключа нет — job честно пропускается.
7. **Обновляемая справка (v1.6 п.5)** — job `updatable-help`: platyPS
   строит внешнюю справку из comment-based (полноту которой гарантирует
   CI-гейт «у каждой публичной команды есть `.SYNOPSIS` и хотя бы один
   `.EXAMPLE`»), MakeCab пакует `Domovoy_<GUID>_<культура>_<версия>.cab`,
   а `Domovoy_<GUID>_HelpInfo.xml` получает `HelpContentURI` на ассет
   релиза. `HelpInfoUri` в манифесте указывает на
   `releases/latest/download`, поэтому `Update-Help -Module Domovoy`
   подтягивает cab новейшего релиза. Job идёт после публикации и не
   блокирует сам релиз — но красный job виден и чинится по-взрослому.

CI (`ci.yml`) проверяет подпись при каждом пуше: если подписи нет —
«unsigned by design» и зелёный статус; если подпись есть — она обязана быть
Valid, битая подпись красит CI. Там же стоит гейт полноты comment-based
справки (SYNOPSIS + EXAMPLE на каждую из публичных команд) — он кормит
обновляемую справку.

## Что нужно от владельца репозитория (когда придёт время)

| Секрет | Что положить | Что включится |
|---|---|---|
| `PSGALLERY_API_KEY` | API-ключ с powershellgallery.com (Account Settings → API Key, scoped на `Domovoy`) | автопубликация релиза в галерею |
| `CODE_SIGNING_PFX` | base64 сертификата подписи кода (.pfx) | подпись ps1/psd1/psm1 + `-signed.zip` в релизе |
| `CODE_SIGNING_PASSWORD` | пароль от .pfx | то же |

До тех пор всё работает без них: релизы выходят, артефакты вкладываются,
CI зелёный. Никаких следов секретов в коде нет — только чтение env.

## Winget: статус и оговорка

Шаблоны манифестов и генератор лежат в `packaging/winget/`; релиз вкладывает
готовые манифесты под свою версию. Публикация в winget — это pull request в
[`microsoft/winget-pkgs`](https://github.com/microsoft/winget-pkgs)
(`manifests/r/Rtynbirf/Domovoy/<версия>/`).

С v1.5.2 манифесты готовы к подаче без ручных правок:

- файл локали назван по требованию валидатора winget-pkgs —
  `Rtynbirf.Domovoy.locale.en-US.yaml` (локаль в имени файла);
- каждый файл манифеста несёт заголовок
  `# yaml-language-server: $schema=https://aka.ms/winget-manifest.<тип>.1.12.0.schema.json`
  — его требует Validation.md winget-pkgs;
- `ManifestVersion` — 1.12.0 (спецификация, на которую ссылается валидатор;
  подъём добавляет ровно одно новое обязательное поле — `DefaultLocale:
  en-US` в version-манифесте, остальные требования для используемых полей
  идентичны — сверено по JSON-схемам winget-cli);
- `NestedInstallerType: portable` целяется в `Domovoy/domovoy.exe` —
  компилируемый exe-шим (`packaging/shim/DomovoyShim.cs`, сборка на CI),
  который резолвит реальный путь своего exe (winget запускает portable
  через symlink из Links-каталога) и форвардит вызов `domovoy.ps1` рядом
  с собой. На `.psd1` portable целяться нельзя — это файл данных; на `.ps1`
  — тоже: см. вердикт ниже.

### Вердикт валидации winget-pkgs (зафиксирован 2026-11-03)

Первый PR ([#469700](https://github.com/microsoft/winget-pkgs/pull/469700),
манифесты v1.5.1 с целью `Domovoy/domovoy.ps1`) получил от пайплайна
валидации ошибку content-валидации. Корневая причина доказана по
исходникам winget-cli: для `NestedInstallerType: portable` допустим ровно
один тип файла — `.exe` (`s_AllowedPortableFiletypes` в
`src/AppInstallerCommonCore/Manifest/ManifestValidation.cpp`, ошибка
`InvalidPortableFiletype: The file type of the referenced file is not
allowed.`). CLA-гейт при этом пройден (`license/cla` success).
Решение — exe-шим, исполнено в v1.5.2 (см. CHANGELOG); гейт CI
«Portable exe shim gate» компилирует шим и доказывает прямую и symlink-
прогонку на каждый пуш, чтобы канал winget не смог протухнуть молча.

Порядок подачи: форк `microsoft/winget-pkgs` аккаунтом владельца → ветка →
три файла в `manifests/r/Rtynbirf/Domovoy/<версия>/` → PR → комментарий
CLA-боту `@microsoft-github-policy-service agree`. Открытый PR
new-package допустимо обновлять до новой версии (замена каталога версии в
том же PR) — их бот сам просит поднимать устаревшие версии; вердикт
модераторов и ботов фиксируется здесь и в ТЗ по мере прихода.

Текущий статус: PR [#469700](https://github.com/microsoft/winget-pkgs/pull/469700)
обновлён до каталога **1.5.2** (2026-11-04, свежий персональный токен
владельца). Замена каталога 1.5.1 → 1.5.2 выполнена одним коммитом
(`de6e945` в ветке `Rtynbirf.Domovoy-1.5.1` — три файла под 1.5.2,
старые удалены; git data API), заголовок поднят до «New package:
Rtynbirf.Domovoy version 1.5.2», в описание и комментарий добавлен вердикт
валидации с корневой причиной ([комментарий](https://github.com/microsoft/winget-pkgs/pull/469700#issuecomment-6612051073)).
Манифесты взяты из релизного ассета `Domovoy-1.5.2-winget-manifests.zip`,
сумма ассета == InstallerSha256 сверена машиной перед отправкой. Дальше —
вердикт ботов валидации и модераторов, фиксируется здесь и в ТЗ по мере
прихода.

## Именование артефактов релиза

| Файл | Что это |
|---|---|
| `Domovoy-<версия>.zip` | модуль + README + LICENSE (всегда) |
| `Domovoy-<версия>-signed.zip` | то же, но с Authenticode-подписью (когда задан сертификат) |
| `Domovoy-<версия>-winget-manifests.zip` | три YAML winget-манифеста этой версии |

SHA256 zip-а зашит в `installer.yaml` — совпадение обязано быть точным.
