# CI failure report

- run: 96 on 9ae68b15a11109f283fdbfeb2a1003e0fcc33df2 (refs/heads/main)

## step trace (the first missing OK names the culprit)
```text
analyzer OK
```

- failed test cases: 1; failed suites: 4

## FAILED: П39 · твик-журнал с гарантированным откатом.живой реестр: твик -> откат -> reg-экспорт байт-в-байт (только Windows).полный цикл: apply меняет, undo возвращает реестр байт-в-байт
```text

```
```text
at Set-RegistryValueTyped, D:\a\domovoy-tweaker\domovoy-tweaker\tools\Invoke-DomovoyTweakJournal.ps1:164
at Set-TweakNewState, D:\a\domovoy-tweaker\domovoy-tweaker\tools\Invoke-DomovoyTweakJournal.ps1:276
at Invoke-DomovoyTweakJournal, D:\a\domovoy-tweaker\domovoy-tweaker\tools\Invoke-DomovoyTweakJournal.ps1:493
at <ScriptBlock>, D:\a\domovoy-tweaker\domovoy-tweaker\tools\Invoke-DomovoyTweakJournal.ps1:504
at <ScriptBlock>, D:\a\domovoy-tweaker\domovoy-tweaker\tests\Domovoy.V15.TweakJournal.Tests.ps1:258
```

## FAILED SUITE: Pester

## FAILED SUITE: D:\a\domovoy-tweaker\domovoy-tweaker\tests\Domovoy.V15.TweakJournal.Tests.ps1

## FAILED SUITE: П39 · твик-журнал с гарантированным откатом

## FAILED SUITE: П39 · твик-журнал с гарантированным откатом.живой реестр: твик -> откат -> reg-экспорт байт-в-байт (только Windows)

