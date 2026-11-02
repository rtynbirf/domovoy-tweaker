# Changelog

Формат — [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/),
версионирование — [SemVer](https://semver.org/lang/ru/).

## [Unreleased]

### Planned (v0.3.0)
- 30+ функций (каталог №17–31): debloat, интерфейс.
- Новые op-типы: `appx.remove`, `file.attribute`.
- Профили: осторожный / стандартный.

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

[Unreleased]: https://github.com/rtynbirf/domovoy-tweaker/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/rtynbirf/domovoy-tweaker/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/rtynbirf/domovoy-tweaker/releases/tag/v0.1.0
