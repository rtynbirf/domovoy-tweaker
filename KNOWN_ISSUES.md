# KNOWN ISSUES · domovoy-tweaker — известные красные и шрамы
> Снимок Волны ×5 (2026-11-09). Живые красные прогоны + известные квирки.

| Что | Статус | Детали | Run/ссылка |
|---|---|---|---|
| CI 08.11 20:17 (df59056) | 🟢 вылечено | тест «полный цикл apply/undo байт-в-байт»: ArgumentException SetValue — JSON-массив разворачивался в object[] | [42519398062](https://github.com/rtynbirf/domovoy-tweaker/actions/runs/42519398062) |
| CI 08.11 20:24 (3a2679f) | 🟢 вылечено | та же орбита | [42519951792](https://github.com/rtynbirf/domovoy-tweaker/actions/runs/42519951792) |
| CI 08.11 20:36 (9ae68b1) | 🟢 вылечено | та же орбита | [42520992561](https://github.com/rtynbirf/domovoy-tweaker/actions/runs/42520992561) |
| CI 08.11 20:42 (c17884d) | 🟢 вылечено | последняя красная до патча | [42521453220](https://github.com/rtynbirf/domovoy-tweaker/actions/runs/42521453220) |
| фикс: SetValue получает Byte[]/String[], а не развёрнутый object[] | ✅ в main | коммит 7173a72, зелёный push-прогон сразу после пуша | [42522295440](https://github.com/rtynbirf/domovoy-tweaker/actions/runs/42522295440) |
| CI 03.11 22:24 (старая орбита) | 🟐 историческая | коммит уже опережён, перезапуск не нужен | [41730503151](https://github.com/rtynbirf/domovoy-tweaker/actions/runs/41730503151) |
| Квирк: реестр-тесты только Windows | ℹ️ по дизайну | Context «живой реестр» -Skip:($env:OS -ne 'Windows_NT'); на Linux/memory-бэкенде реестр не репро-нется | tests/Domovoy.V15.TweakJournal.Tests.ps1 |
| Квирк: PSScriptAnalyzer 0 warning — приёмочный гейт | ℹ️ по дизайну | любые правки tools/ держать чистыми по PSScriptAnalyzerSettings.psd1 | CI job Lint + Test |
