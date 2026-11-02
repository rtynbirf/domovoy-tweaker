<!-- Один PR - одна тема. Заголовок - по Conventional Commits
     (feat: / fix: / docs: / test: / chore: / refactor:). -->

## Чек-лист

- [ ] Манифест(ы) проходят схему: `Invoke-Pester tests/Domovoy.Manifest.Tests.ps1`
- [ ] Для каждого нового op-типа - все 4 проекции (plan / snapshot / execute / undo)
- [ ] Пробы `verify` добавлены и реализованы в `Test-DomovoyEffect`
- [ ] Строка в `docs/features.md` обновлена, номер в каталоге присвоен
- [ ] Секция в `CHANGELOG.md` добавлена
- [ ] Сетевых вызовов нет (инвариант I4)
- [ ] `.ps1/.psm1/.psd1` - только ASCII
- [ ] PSScriptAnalyzer - 0 ошибок уровня Error
