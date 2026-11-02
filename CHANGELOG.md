# Changelog

Формат — [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/),
версионирование — [SemVer](https://semver.org/lang/ru/).

## [Unreleased]

### Planned (v0.6.0)
- Авто-лечение дрейфа (opt-in, по расписанию, журнал каждого действия).
- Упаковка: PSGallery, winget; каталог №34, 43, 47–48, 50, 52, 58.

## [0.5.0] — 2026-11-02

### Added
- Отчёт «что реально изменилось» по apply: результат `Invoke-DomovoyFeature
  -Apply` несёт `Changes` — для каждой пробы значение **до** (из снимка,
  зафиксированного до первой операции) и **после** (из проб, запущенных
  сразу после последней), плюс признак `Changed`. Повторный apply того же
  манифеста честно показывает `Changed = false`.
- 100% покрытие манифестов пробами: новая проба `appx.present` (№24 —
  «пакет действительно присутствует»), тест гейтит, что каждый verify-тип
  всех манифестов реализован в `Test-DomovoyEffect`, и CI гоняет пробы по
  каждой функции — ни одного «unknown-probe».
- Отчёты только для чтения (ничего не меняют): `Get-DomovoyTelemetryReport`
  (№15 — фактические значения всех телеметрических политик одним списком),
  `Get-DomovoyStartupInventory` (№41 — документированные Run/RunOnce),
  `Get-DomovoyDriverInventory` (№45; с `-Export` — №42, JSON-снимок
  драйверов в хранилище), `Get-DomovoyBitLockerStatus` (№49 — только
  отображение состояния, честная ошибка без elevation), `Get-DomovoyChangeReport`
  (№63 — «что изменилось с момента X» по журналу, с датами).
- Действия с dry-run по умолчанию и записью факта в журнал:
  `Invoke-DomovoyNetworkReset` (№32 — winsock/IP; снимаются и восстанавливаются
  все настройки, которые МОЖНО снять — статические IP и DNS; сам каталог
  Winsock необратим, и это сказано прямо; `Undo-DomovoyNetworkReset`
  восстанавливает снимок),
  `Invoke-DomovoyEventLogCleanup` (№38 — сначала отчёт «сколько записей»,
  очистка только с `-Apply`, факт и измеренные «до/после» в журнал),
  `Invoke-DomovoyMemoryTrim` (№40 — EmptyWorkingSet с честной пометкой
  «эффект временный», измеренные байты до/после),
  `Invoke-DomovoySystemIntegrityCheck` (№51 — sfc/DISM, полный вывод в
  хранилище, код выхода и файл в журнал).
- «До/после» для очистки temp стало полным и измеримым (№44): отчёт apply
  несёт `FilesFound`/`BytesFound` (до), `FilesRemoved`/`BytesFreed` и
  `BytesAfter` — фактический пересчёт остатка, а не арифметика.
- Новые события журнала: `networkreset.apply`, `eventlog.cleanup.apply`,
  `memorytrim.apply`, `integritycheck.apply`.

## [0.4.0] — 2026-11-02

### Added
- Дозор дрейфа — полный контур (каталог №57, №5): базовая линия берётся из
  последнего **verified-снимка в журнале** (пробы, зафиксированные сразу после
  apply), а не из манифеста. Отчёт содержит функцию, дату применения, дату
  обнаружения и деталь расхождения `{probe, target, verified, expected,
  actual, pass}`; `-Since` ограничивает скан функциями, применёнными после
  момента X; функции, последнее событие которых — undo, не сканируются.
  E2E-тест имитирует «обновление вернуло политику» и требует, чтобы скан
  поймал дрейф.
- Op `scheduler.task` с полными четырьмя проекциями (op/probe/snapshot/undo)
  и проба `scheduler.taskState`: отключение задач планировщика по явному
  списку, только состояние задачи, undo возвращает прежнее состояние (№7, №5).
- 5 новых функций (итого 26): телеметрические задачи планировщика
  (`scheduler.telemetry-tasks.disabled`), сводная блокировка отправки
  диагностики (`policy.diagnostics.sending.blocked`, №14), Edge startup
  boost/background mode по документированным политикам
  (`policy.edge.background.disabled`, №18), настройка панели задач Windows 11
  (`ui.taskbar.cleanup`, №28), отключение «советов Windows»
  (`policy.windows-tips.disabled`, №30).
- `Invoke-DomovoyCleanup` (№37): сначала отчёт «сколько освободим» (dry-run
  по умолчанию), удаление старых файлов в temp — только с `-Apply`.
  Необратимо по дизайну, поэтому не манифест: факт, объём и неудачные файлы
  фиксируются новым событием журнала `cleanup.apply`.
- `appx.remove` undo: если файлы пакета уже удалены, выводит подсказку
  документированного источника восстановления (Store/winget) вместо молчания
  (№20; сам модуль по-прежнему ничего не скачивает — I4).

## [0.3.1] — 2026-11-02

### Fixed
- `file.attribute`: применение, верификация и undo снова «видят» скрытые файлы.
  В PowerShell `Get-Item` без `-Force` не находит файл с атрибутом Hidden:
  apply с `Hidden` падал с «IOException: Could not find item» (красный CI на
  windows-latest), а undo молча пропускал восстановление. `Test-Path` скрытые
  файлы видит и параметра `-Force` не имеет (#1).

## [0.3.0] — 2026-11-02

### Added
- Новые op-типы с полными четырьмя проекциями (op/probe/snapshot/undo):
  `appx.remove` (undo — пере-регистрация пакета из места установки, без сети,
  честный отчёт, если файлов уже нет) и `file.attribute` (undo — точный
  прежний набор атрибутов).
- Новые пробы: `appx.absent`, `file.attributes`.
- Профили — декларативные JSON-пакеты с потолком риска (maxRisk):
  «осторожный» (low) и «стандартный» (medium). `Get-DomovoyProfile`,
  `Invoke-DomovoyProfile`: суммарный dry-run-план по умолчанию; при `-Apply` —
  одна точка восстановления на профиль и честный отчёт о пропущенных
  функциях (критерий вехи: «профиль — JSON, а не скрипт»).
- 11 новых функций (итого 21): Store-пакеты (OneDrive sync, Chat, Xbox Game
  Bar overlay + политика Game DVR, Cortana, Get Help, Tips), классическое
  контекстное меню Windows 11, показ расширений и скрытых файлов,
  отключение панели Виджетов по политике, телеметрия рукописного/речевого
  ввода, облачный поиск.
- `Backup-DomovoyServiceState` — экспорт всей таблицы служб в JSON (каталог №8;
  ответ на идею экспорта из 2.0 `Exportext`/3.0 `Exportdrv`).
- Undo `registry.set` теперь удаляет и пустые ключи, созданные самим твиком
  (в снапшоте `pathExisted`, подъём по пустой цепочке — spec §9.1 v0.3).
- Схема профилей `schema/profiles.schema.json`; CI валидирует профили наряду
  с манифестами.

### Changed
- Модуль: 12 публичных команд (было 9).
- Снапшот `registry.set` дополнен полем `pathExisted` (обратно совместим:
  старые записи журнала разбираются без него).

## [0.2.0] — 2026-11-02

### Added
- Журнал (Ledger) и откат как полностью рабочий контур: append-only JSONL,
  snapshots, per-feature undo — покрыто E2E-тестами apply → verify → undo.
- Новые op-типы с полными четырьмя проекциями (op/probe/snapshot/undo):
  `registry.delete` и `service.stop`; новые пробы: `registry.absent`, `service.status`.
- 8 новых документированных функций (итого 10): dmwappushservice, RemoteRegistry,
  уведомления обратной связи, advertising ID, tailored experiences,
  consumer features, Cortana, файловая синхронизация OneDrive.
- `featureSource` в журнале: undo и дозор работают даже если манифест вне каталога.
- Undo останавливённых служб: если служба была Running до твика — запускается при откате.
- E2E-тесты: точные значения и типы восстанавливаются; значение, которого не было,
  удаляется при undo; журнал переживает битую строку.

### Changed
- `toolVersion` в журнале берётся из версии модуля, а не зашито в код.
- Undo находит манифест через `featureSource` из журнала, если функции нет в каталоге.

### Fixed
- Cosmetic: единичный обратный слеш в отображении цели пробы.

## [0.1.0] — 2026-11-02

### Added
- Скелет прототипа: PowerShell-модуль `Domovoy` — 9 публичных команд, 5 приватных помощников.
- Скелеты четырёх контуров: Журнал (JSONL), Машина времени (undo из снимков), Дозор (drift scan), Проверка эффекта (пробы).
- Формат манифеста функции (JSON) + JSON-схема + 2 эталонных манифеста:
  отключение службы DiagTrack и политика AllowTelemetry=0.
- Pester-тесты (валидация манифестов, парсинг исходников, dry-run без прав администратора).
- CI на GitHub Actions: PSScriptAnalyzer (гейт по Error), Pester, валидация манифестов по схеме.
- Документация: спецификация, архитектура, дорожная карта, полный нумерованный каталог
  функций (64 позиции), сравнение с мировой практикой, кейс-стади реверс-инжиниринга
  Modern Tweaker 2.0 → 3.0.

[Unreleased]: https://github.com/rtynbirf/domovoy-tweaker/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/rtynbirf/domovoy-tweaker/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/rtynbirf/domovoy-tweaker/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/rtynbirf/domovoy-tweaker/releases/tag/v0.1.0
