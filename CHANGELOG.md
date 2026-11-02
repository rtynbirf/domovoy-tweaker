# Changelog

Формат — [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/),
версионирование — [SemVer](https://semver.org/lang/ru/).

## [Unreleased]

### Planned (v0.4.0)
- Дозор: базовая линия из последнего verified-снимка (не из манифеста).
- Каталог №5, 18, 20, 28, 30, 37.
- Новые op-типы: `scheduler.task`.

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
