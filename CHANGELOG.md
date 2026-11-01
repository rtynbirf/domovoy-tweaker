# Changelog

Формат — [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/),
версионирование — [SemVer](https://semver.org/lang/ru/).

## [Unreleased]

### Planned (v0.2.0)
- Журнал (Ledger) и откат как полностью рабочий контур: append-only JSONL, snapshots, undo.
- Первые 10 функций категории «Службы» и «Приватность».
- Dry-run по умолчанию для всех операций.

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

[Unreleased]: https://github.com/rtynbirf/domovoy-tweaker/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/rtynbirf/domovoy-tweaker/releases/tag/v0.1.0
