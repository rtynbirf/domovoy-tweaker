function Get-DomovoyStrings {
    <#
    .SYNOPSIS
    Returns the user-facing string table for the active language (v1.6 item 6).

    .DESCRIPTION
    The presentation layer of Domovoy - the GUI and the human summaries of
    the key reports - reads every user-visible sentence from this table
    instead of hard-coded literals. Two languages ship today: 'en' (the
    default, identical wording to the pre-localization releases) and 'ru'.
    The table is data, not logic: the language switch changes which strings
    are returned, never which commands run.

    Resolution order for the active language:
    1. the session override set by Set-DomovoyLanguage (a module-level
       variable - lives for the session, survives nothing);
    2. the stored preference file <store>\language.txt written by
       Set-DomovoyLanguage (read on every call, never cached - cheap, and
       it cannot go stale between test suites that swap the store);
    3. 'en' - the documented default.

    .NOTES
    This file carries Cyrillic text, so it is saved as UTF-8 with a BOM:
    Windows PowerShell 5.1 (the experimental CI leg) reads non-BOM UTF-8
    through the system ANSI codepage and would mangle every RU string.

    .EXAMPLE
    $s = Get-DomovoyStrings
    $s.windowTitle
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $tables = @{
        en = @{
            windowTitle      = 'Domovoy - the ledger-based Windows tweaker'
            columnId         = 'Id'
            columnTitle      = 'Title'
            columnRisk       = 'Risk'
            columnJournal    = 'Journal'
            welcome1         = 'Domovoy GUI - thin client over the CLI (module {0}).'
            welcome2         = 'Every action below first prints the CLI command it runs, then runs exactly that command.'
            btnDryRun        = 'Dry-run'
            btnApply         = 'Apply...'
            btnUndo          = 'Undo...'
            btnEffect        = 'Effect'
            btnDriftScan     = 'Drift scan'
            btnChangeReport  = 'Change report'
            btnNetworkReport = 'Network report'
            btnAutoHeal      = 'Auto-heal (dry-run)'
            btnSwitchTheme   = 'Switch theme'
            btnExportPolicies = 'Export policies'
            btnRefresh       = 'Refresh'
            btnLanguage      = 'Language: {0}'
            selectFirst      = 'Select a feature first.'
            cancelled        = 'Cancelled.'
            noOutput         = '(no output)'
            cliPrefix        = 'CLI: '
            errorPrefix      = 'ERROR: '
            refreshed        = 'Feature list refreshed.'
            applyConfirm     = "Run: {0}`n`nA snapshot is taken before the change; undo stays available."
            undoConfirm      = 'Run: {0}'
            themeConfirm     = "Run: {0}`n`nThe theme toggles between dark and light; the previous values stay undo-able."
            messageBoxTitle  = 'Domovoy'
            languageSwitched = 'Language switched to {0}. Reopen the window to relabel every control.'
            reportStoreInitialized = 'store initialized'
            reportFeatureApplied   = 'feature applied, verified: {0}'
            reportFeatureUndone    = 'feature undone from snapshot'
            reportCleanup          = 'cleanup: {0} files, {1} bytes freed, {2} failed'
            reportNetworkReset     = 'network reset ({0}); static settings snapshot recorded'
            reportEventlogCleanup  = 'event logs cleared: {0} entries -> {1} entries'
            reportMemoryTrim       = 'memory trim: {0} processes, {1} bytes before, {2} bytes after'
            reportIntegrityCheck   = 'integrity check ({0}) exit code {1}'
            reportEventDefault     = 'event'
            reportUnknownPass      = '<unknown>'
            searchLabel       = 'Search:'
            filterCount       = 'Shown: {0} of {1}'
            statusReady       = 'Ready.'
            statusRunning     = 'Running: {0}'
            statusCancelled   = 'Cancelled.'
            stopRequested     = 'Cancelling...'
            busySkip          = 'Another operation is running - wait for it or press Stop.'
            btnStop           = 'Stop'
            journalApplied    = 'applied'
            journalUndone     = 'undone'
            adminStatusAdmin  = 'Session: administrator'
            adminStatusUser   = 'Session: regular user'
            btnElevate        = 'Restart as administrator...'
            elevateStarted    = 'Elevated window requested - confirm the UAC prompt.'
            elevateFailed     = 'Elevation failed or was cancelled: {0}'
            welcomeNoAdmin    = 'Some features (services, HKLM) need administrator rights - if a change fails, use Restart as administrator.'
            fatalErrorTitle   = 'Domovoy - unexpected error'
            fatalErrorBody    = "An unexpected error occurred:`n`n{0}`n`nTechnical log: {1}`n`nYes - copy the details to the clipboard, No - close. Please file an issue: https://github.com/rtynbirf/domovoy-tweaker/issues"
            errorCopied       = 'Error details copied to the clipboard.'
        }
        ru = @{
            windowTitle      = 'ДОМОВОЙ — твикер Windows на основе журнала'
            columnId         = 'Ид'
            columnTitle      = 'Название'
            columnRisk       = 'Риск'
            columnJournal    = 'Журнал'
            welcome1         = 'ДОМОВОЙ GUI — тонкий клиент над CLI (модуль {0}).'
            welcome2         = 'Каждое действие ниже сначала печатает CLI-команду, которую выполняет, затем выполняет ровно её.'
            btnDryRun        = 'Пробный прогон'
            btnApply         = 'Применить...'
            btnUndo          = 'Откатить...'
            btnEffect        = 'Отчёт об эффекте'
            btnDriftScan     = 'Скан дрейфа'
            btnChangeReport  = 'Отчёт об изменениях'
            btnNetworkReport = 'Сетевой отчёт'
            btnAutoHeal      = 'Автоисцеление (пробный)'
            btnSwitchTheme   = 'Сменить тему'
            btnExportPolicies = 'Экспорт политик'
            btnRefresh       = 'Обновить'
            btnLanguage      = 'Язык: {0}'
            selectFirst      = 'Сначала выберите фичу в списке.'
            cancelled        = 'Отменено.'
            noOutput         = '(нет вывода)'
            cliPrefix        = 'CLI: '
            errorPrefix      = 'ОШИБКА: '
            refreshed        = 'Список фич обновлён.'
            applyConfirm     = "Запуск: {0}`n`nПеред изменением снимается снимок состояния; откат остаётся доступным."
            undoConfirm      = 'Запуск: {0}'
            themeConfirm     = "Запуск: {0}`n`nТема переключается между тёмной и светлой; прежние значения остаются откатываемыми."
            messageBoxTitle  = 'ДОМОВОЙ'
            languageSwitched = 'Язык переключён на «{0}». Откройте окно заново, чтобы обновились все надписи.'
            reportStoreInitialized = 'хранилище инициализировано'
            reportFeatureApplied   = 'фича применена, верификация: {0}'
            reportFeatureUndone    = 'фича откачена по снимку'
            reportCleanup          = 'очистка: файлов {0}, байт освобождено {1}, сбоев {2}'
            reportNetworkReset     = 'сброс сети ({0}); снимок статических настроек записан'
            reportEventlogCleanup  = 'журналы событий очищены: записей {0} -> {1}'
            reportMemoryTrim       = 'подрезка памяти: процессов {0}, байт до {1}, байт после {2}'
            reportIntegrityCheck   = 'проверка целостности ({0}) код выхода {1}'
            reportEventDefault     = 'событие'
            reportUnknownPass      = '<неизвестно>'
            searchLabel       = 'Поиск:'
            filterCount       = 'Показано: {0} из {1}'
            statusReady       = 'Готово.'
            statusRunning     = 'Выполняется: {0}'
            statusCancelled   = 'Отменено.'
            stopRequested     = 'Отмена...'
            busySkip          = 'Уже выполняется другая операция — подождите или нажмите «Стоп».'
            btnStop           = 'Стоп'
            journalApplied    = 'применена'
            journalUndone     = 'откачена'
            adminStatusAdmin  = 'Права: администратор'
            adminStatusUser   = 'Права: обычный сеанс'
            btnElevate        = 'Перезапустить от администратора...'
            elevateStarted    = 'Запрошено окно с правами администратора — подтвердите UAC.'
            elevateFailed     = 'Не удалось запросить права администратора: {0}'
            welcomeNoAdmin    = 'Часть фич (службы, HKLM) требует прав администратора — если изменение не применяется, нажмите «Перезапустить от администратора...».'
            fatalErrorTitle   = 'ДОМОВОЙ — непредвиденная ошибка'
            fatalErrorBody    = "Произошла непредвиденная ошибка:`n`n{0}`n`nТехнический журнал: {1}`n`nДа — скопировать подробности в буфер обмена, Нет — закрыть. Создайте issue: https://github.com/rtynbirf/domovoy-tweaker/issues"
            errorCopied       = 'Подробности об ошибке скопированы в буфер обмена.'
        }
    }

    # The documented default is applied BEFORE the table lookup:
    # ContainsKey must never see a null key. With a fresh store and no
    # session override $language used to reach the lookup as $null and
    # threw on PS 7.6 (ArgumentNullException at Get-DomovoyStrings:141 -
    # CI runs 54/55: the GUI-preview and change-report paths of OTHER
    # suites read the table without ever setting a language, which is
    # exactly the branch the language suite never covered).
    $language = 'en'
    if ($script:DomovoyLanguage) {
        $language = [string]$script:DomovoyLanguage
    }
    else {
        try {
            $prefFile = Join-Path -Path (Get-DomovoyStorePath) -ChildPath 'language.txt'
            if (Test-Path -LiteralPath $prefFile) {
                $stored = (Get-Content -LiteralPath $prefFile -Encoding UTF8 -ErrorAction Stop | Select-Object -First 1)
                if ($stored) { $language = ([string]$stored).Trim().ToLowerInvariant() }
            }
        }
        catch {
            # An unreadable store never breaks the presentation layer -
            # the resolver falls through to the documented default.
            $language = $null
        }
    }

    if (-not $tables.ContainsKey($language)) {
        $language = 'en'
    }
    return $tables[$language]
}
