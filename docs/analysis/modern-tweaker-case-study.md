# Кейс-стади: реверс-инжиниринг Modern Tweaker 2.0 → 3.0

Статус: завершено · Метод: **только статический анализ** (бинарники не запускались) ·
Обновлён: 2026-11-02

Это исследование — фундамент принципов ДОМОВОГО. Два приложения, один проект,
три года разницы — и три урока, из которых вырос весь замысел.

---

## 1. Образцы

| | Modern Tweaker 2.0 Final Portable | Modern Tweaker 3.0 Portable |
|---|---|---|
| SHA-256 | `aa1522146b2be7aec425d9801b93f7848aad8cda67b41f005a416dd3396b6bfa` | `347a668c0e90c0bf418baed1371fa520c2d8226a7e5ddac08b2c05985e35076d` |
| Размер | 1.34 MB | 2.12 MB |
| Формат | PE32, .NET 4.7.2, WinForms, x86 | PE32, .NET 4.7.2, WinForms |
| Компиляция (PE timestamp) | 2023-12-29 | 2026-08-17 09:53 UTC |
| Подпись | `CN=mixmar` (Sectigo-цепочка в бинарнике) | `O=Modern Tweaker` (DigiCert-цепочка) |
| Защита | SmartAssembly 8.2.0.5183 | koi-protector: заглушка ~40 KB + сжатый блок ~2 MB (энтропия 8.00, LZMA) + ENCLog/ENCMap + AES |
| Метаданные | открыты: 568 типов, 2788 методов, 2636 поля; 12 AssemblyRef; 62 P/Invoke из 8 DLL | скрыты упаковщиком; читаются только UI-слои |

## 2. Что мы увидели в 2.0 (открытая книга)

Метаданные открыты SmartAssembly'ем не полностью (строки/члены перемешаны), но
структура читается. Восстановленные категории:

- **Службы:** `OpenSCManager`, `OpenService`, `QueryServiceConfig`, `ChangeServiceConfig`,
  `StartService`, `ServiceController`, `ServiceDepend`/`dependService`/`delDepend`,
  `nameService` — полное управление службами с зависимостями.
- **Defender:** `StopDef`, `StartDef`, `DefKill`, `Defdop`.
- **Удаление приложений:** `OneDrive`, `DeleteEdge`, `Udal1`–`Udal5` (пять пакетов удаления).
- **Процессы:** `KillThemAll`, `GetProcessesByName`, `Kill`, `Terminate`, `OpenProcess`.
- **Реестр:** `CreateSubKey`, `DeleteSubKey`, `DeleteSubKeyTree`, `RegistrySecurity`,
  `RegistryAccessRule` — включая правку ACL ключей.
- **Привилегии/Token:** `AdjustTokenPrivileges` (×5 вызовов), `DuplicateTokenEx`,
  `SetTokenInformation`, `LookupPrivilegeValue`, `CreateEnvironmentBlock`,
  `CreateProcessAsUserW`, `CreateProcessWithTokenW`, `WTSGetActiveConsoleSessionId`,
  `NtSetSystemInformation`, `TILauncher`/`TrustedInstaller` — полная цепочка
  заимствования токена TrustedInstaller.
- **Файлы/архивы:** `MoveFileEx`, `ZipFile`, `ExtractToDirectory`, `DriveInfo`.
- **Сеть:** `WebClient`, `DownloadFile`, `DownloadString`,
  **`RemoteCertificateValidationCallback` + `ServicePointManager` + `SslPolicyErrors`**
  — колбэк, позволяющий игнорировать ошибки TLS-сертификатов.
- **Прочее:** `BitLocker`, `SysLog`/`ClearLog`, `Attrib_off`, `Personal`/`Personal1`,
  `Cleaner`/`Cleaner1`, `Runcmd`, `Exportext`/`Importext`, `RunTest` (ядро, 26 методов),
  `SpeechSynthesizer`, `Clipboard.SetText`.

## 3. Что изменилось в 3.0 (закрытая книга)

- Функциональное ядро преемственно (сервисы, реестр-пакеты `Setupreg`/`UpReestr`/`RemoveReestr`,
  привилегии `PrivilegesNative`, драйверы `Exportdrv`/`RemoveDubOldDrivers`, память `EmptyWorkingSet`).
- **Новое:** скины/темы (`SimpleSkin`, `SimpleSkinManager`, `SimpleFlatButton`,
  `SimpleCheckBox`, `SimpleProgressBar`, …), уведомления (`SimpleNotify`),
  оверлей операций (`ScreenBlocker`), сплэш (`SplashScreenLoading`),
  GPO-слой (`IGroupPolicyObject`, `ComputerGroupPolicyObject`, `GroupPolicySection`),
  JSON-конфиг (`SimpleJson`/`JSONParser`/`JSONWriter`), анти-отладка (`Debugger`,
  `FailFast`, `get_IsAttached`), `VirtualProtect`.
- **Главное отличие — не функции, а прозрачность:** 2.0 читался за вечер;
  3.0 упакован, зашифрован и защищён от анализа.

## 4. Три урока → три принципа ДОМОВОГО

| Наблюдение | Урок | Принцип |
|---|---|---|
| 3.0 сделал интерфейс красивее, но «дом» стало не видно: упаковка, шифрование, анти-отладка | сила без видимости = distrust по умолчанию | **Принцип 7:** код открыт и читается за вечер; обфускация — в списке «никогда» |
| Ни 2.0, ни 3.0 не помнят: что было ДО, что стало ПОСЛЕ; откат — «переустанови систему» | твик без памяти — это выстрел, а не настройка | **Контуры 1–2:** Ledger + per-feature undo из снимка |
| `WebClient` + колбэк игнорирования TLS-ошибок в 2.0 | сетевой контур внутри твикера — это дыра в каждой точке применения | **Инвариант I4:** нулевая сеть в модуле, навсегда |

## 5. Методология (воспроизводимость)

Чистая статика, без исполнения: PE-заголовки и timestamp, ASCII/UTF-16 строки,
разбор метаданных .NET (#Strings/#US/#Blob, TypeDef/MethodDef/Field),
AssemblyRef, таблица P/Invoke, региональная энтропия (обнаружение LZMA-блока),
Authenticode-цепочки. Артефакты анализа сохранены у автора; в репозиторий
намеренно вынесены только факты, а не дампы содержимого чужого кода.
