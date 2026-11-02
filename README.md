# ДОМОВОЙ · МЕГА=ТВИКЕР

> Твикер Windows как **состояние**, а не **событие**. Прототип на PowerShell.

![CI](https://github.com/rtynbirf/domovoy-tweaker/actions/workflows/ci.yml/badge.svg)
![License](https://img.shields.io/badge/license-MIT-blue)
![Platform](https://img.shields.io/badge/platform-Windows%2010%2F11-lightgrey)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207%2B-5391FE)

## Что это

Обычные твикеры — и все «учителя», у которых мы учились, — работают как **событие**:
нажал кнопку → применил твик → закрыл. Что именно изменилось в системе, что было ДО,
вернулось ли всё на место после очередного обновления Windows — не помнит никто.

ДОМОВОЙ устроен как дух дома: он ведёт хозяйство и **помнит всё**. Твик для него —
не клик, а **состояние**, зафиксированное в журнале, которое можно проверить,
откатить и защитить от дрейфа.

Родословная: прототип вырос из реверс-инжиниринга Modern Tweaker 2.0/3.0
(см. [кейс-стади](docs/analysis/modern-tweaker-case-study.md)) и изучения четырёх
мировых практик — Sophia Script, WinUtil, Win11Debloat, privacy.sexy
([сравнение](docs/comparison.md)).

## Четыре контура

| Контур | Что делает | Статус |
|---|---|---|
| 📜 **Журнал** (Ledger) | Каждое изменение: кто, когда, что было ДО, что стало ПОСЛЕ. Append-only JSONL | ✅ рабочий с v0.2 |
| 🔭 **Дозор** (Drift Sentinel) | Сравнивает фактическое состояние с зафиксированным — ловит откат твиков после обновлений Windows | скелет с v0.1, базовая линия из снимков в v0.4 |
| ⏪ **Машина времени** | Откат любой функции по отдельности, из снимка ДО, а не «снести всё» | ✅ рабочий с v0.2 |
| ✅ **Проверка эффекта** | Пробы (значение/отсутствие в реестре, тип запуска и статус службы) — прошло / не прошло, честно | базово работает с v0.2, полный в v0.5 |

## Принципы (без них смысла нет)

1. Твик = состояние в журнале, а не клик в интерфейсе.
2. Каждая функция обязана иметь откат из снимка, сделанного ДО применения.
3. Только документированные пути (реестр, службы, политики) — ссылка на источник в каждом манифесте.
4. Ничего не скачивается во время применения — нулевой Web-контур, прямой ответ на `WebClient.DownloadString` из 2.0.
5. Dry-run по умолчанию: без явного `-Apply` показывается только план изменений.
6. Идемпотентность: повторное применение ничего не ломает.
7. Код открыт и читается за вечер; каждое действие объясняет само себя.

## Структура репозитория

```
domovoy-tweaker/
├── README.md, LICENSE, CHANGELOG, CONTRIBUTING, CODE_OF_CONDUCT, SECURITY
├── .github/workflows/            # ci.yml + release.yml (тег → релиз)
├── docs/
│   ├── spec.md                   # техническая спецификация
│   ├── architecture.md           # четыре контура, схемы, алгоритмы
│   ├── roadmap.md                # вехи с критериями приёмки
│   ├── features.md               # ПОЛНЫЙ нумерованный каталог функций (64)
│   ├── comparison.md             # сравнение с Sophia/WinUtil/Win11Debloat/privacy.sexy
│   └── analysis/
│       └── modern-tweaker-case-study.md   # реверс-инжиниринг 2.0 → 3.0 (статика)
├── schema/
│   ├── features.schema.json      # JSON-схема манифеста функции
│   └── profiles.schema.json      # JSON-схема профиля
├── config/
│   ├── features/                 # манифесты функций (21: службы, приватность, debloat, интерфейс)
│   └── profiles/                 # профили cautious / standard (JSON, не скрипты)
├── src/Domovoy/                  # модуль PowerShell (12 публичных команд)
└── tests/                        # Pester
```

## Быстрый старт

```powershell
git clone https://github.com/rtynbirf/domovoy-tweaker.git
cd domovoy-tweaker
Import-Module ./src/Domovoy/Domovoy.psd1 -Force

Initialize-Domovoy
Get-DomovoyFeature                                        # каталог функций
Invoke-DomovoyFeature -Id services.diagtrack.disabled     # dry-run: план + снимок
Invoke-DomovoyFeature -Id services.diagtrack.disabled -Apply   # применить + записать в журнал
Get-DomovoyLedger                                         # что произошло
Test-DomovoyEffect -Id services.diagtrack.disabled        # пробы эффекта
Undo-DomovoyFeature -Id services.diagtrack.disabled -Apply     # откат из снимка
Invoke-DomovoyDriftScan                                   # есть ли дрейф

Get-DomovoyProfile                                        # профили: cautious / standard
Invoke-DomovoyProfile -Id cautious                        # суммарный dry-run-план профиля
Invoke-DomovoyProfile -Id cautious -Apply                 # применить профиль (одна точка восстановления)
Backup-DomovoyServiceState                                # экспорт таблицы служб в JSON
```

Требуется Windows 10/11, PowerShell 5.1 или 7+; для `-Apply` — сессия с правами администратора.

## Дорожная карта

Вехи с критериями приёмки — в [docs/roadmap.md](docs/roadmap.md).
Сейчас: **v0.3.0** — 21 функция (службы, приватность, debloat, интерфейс),
профили cautious/standard (JSON + потолок риска), op-типы `appx.remove` и
`file.attribute` с 4 проекциями, экспорт таблицы служб.
Дальше: v0.4.0 — Дозор с базовой линией из снимков; v1.0.0 — 100+ функций и стабильный API.

## Отказ от ответственности

Прототип. Менять реестр и службы — значит брать на себя ответственность за свою систему.
Создавайте точки восстановления (модуль при `-Apply` делает это сам).
Проект не аффилирован с Microsoft. Windows — товарный знак Microsoft.

## Лицензия

[MIT](LICENSE).

<details>
<summary>English summary</summary>

Domovoy ("house spirit") is a Windows tweaker prototype that treats a tweak as a
*state*, not an *event*: an append-only change ledger, per-feature undo from
pre-change snapshots, a drift sentinel that detects rollbacks after Windows
Updates, and effect-verification probes. It grew from static reverse-engineering
of Modern Tweaker 2.0/3.0 and lessons from Sophia Script, WinUtil, Win11Debloat
and privacy.sexy. PowerShell 5.1+/7, dry-run by default, no runtime downloads.
See `docs/` for the spec, architecture, roadmap and the full numbered feature catalog.
</details>
