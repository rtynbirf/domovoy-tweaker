# Экспорт в GPO/Intune-совместимые политики (v0.7.0, каталог №62)

`Export-DomovoyPolicy` берёт из журнала последний `feature.apply` каждой фичи,
оставляет проверенные пробами (парамерт `-IncludeUnverified` отключает фильтр)
и выгружает реестровую часть их манифестов в стандартный Group Policy-бандл.
Идея GPO-слоя Modern Tweaker 3.0 (`IGroupPolicyObject` внутри закрытого
бинарника) переосмыслена в сторону стандартов: никаких обёрток — обычные
`.admx`/`.adml`/`Registry.pol`, которые читает сам Windows.

## Состав экспорта

| Файл | Что это |
|---|---|
| `Domovoy.admx` | административный шаблон: категория `Domovoy`, одна политика на фичу |
| `en-US\Domovoy.adml` | строковые ресурсы шаблона (названия/описания фич) |
| `Machine-Registry.pol` | бинарный PReg-файл для значений HKLM (класс Machine) |
| `User-Registry.pol` | бинарный PReg-файл для значений HKCU (класс User) |
| `policy-mapping.csv` | каждая выгруженная величина: фича, класс, ключ, значение, тип, данные |
| `README.md` | инструкция по загрузке в gpedit/GPO/Intune |

Формат `Registry.pol` (PReg) — документированный: заголовок `PReg` + версия 1,
записи `[ключ;значение;тип;размер;данные]` в UTF-16LE. Кодировщик и парсер —
чистая собственная реализация на байтах, без внешних инструментов (инвариант
«чужих бинарников не запускаем»). Удаления значений выгружаются стандартным
маркером GP `**Del.<имя>`.

## Самопроверка перед отчётом

Экспорт заканчивается self-check: оба `.pol`-файла разбираются собственным
парсером обратно в записи (round-trip), `.admx`/`.adml` грузятся как XML.
Итог — в поле `SelfCheck` результата (`pass (PReg round-trip + XML
well-formed)`).

## Загрузка в gpedit (локально)

1. `Domovoy.admx` → `%windir%\PolicyDefinitions\`, `en-US\Domovoy.adml` →
   `%windir%\PolicyDefinitions\en-US\`.
2. Открыть `gpedit.msc`: под Administrative Templates появится категория
   `Domovoy`.
3. Критерий вехи: шаблон открывается без ошибок; включение политики пишет
   ровно то значение, которое Домовой проверил пробами.

## Загрузка в доменный GPO

1. `Domovoy.admx` → `\\<домен>\SYSVOL\<домен>\Policies\PolicyDefinitions\`,
   `en-US` рядом.
2. `Machine-Registry.pol` → в папку GPO `Machine\`, `User-Registry.pol` → в
   `User\` (в свежем GPO этих файлов ещё нет — создать из экспорта).

## Intune

- Ingestion ADMX: загрузить `Domovoy.admx` документированным OMA-URI
  `Policy/ConfigOperations/ADMXInstall/Domovoy/Policy/DomovoyAdmx`, дальше —
  Settings catalog.
- Напрямую: `policy-mapping.csv` — каждая строка это одно значение
  HKLM/HKCU, которое можно enforced OMA-URI или PowerShell-remediation.

## Конфликты и честные ограничения

- Если две фичи требуют одно значение реестра — выгружается **последняя
  применённая**, а перезапись попадает в `Conflicts` отчёта экспорта.
- Службы, Appx, DNS, планировщик, файлы и привилегии не выражаются в
  Administrative Templates — они остаются в журнале Домового и попадают в
  `Skipped` (не молча).
- `Binary`/`MultiString`/`QWord`/`ExpandString` идут через `Registry.pol`,
  но ADMX-элемента для них нет (в каталоге таких манифестов сейчас нет).
- Значения `(default)` идут только в `.pol` (пустое имя в PReg).
- Нестандартные пути вне `...\Policies\` выгружаются как есть: gpedit их
  грузит, но формально это зона за пределами классических ADMT-настроек.
