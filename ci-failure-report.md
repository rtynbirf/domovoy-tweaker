# CI failure report

- run: 97 on c17884da040eae037e3534332030c22c7d166444 (refs/heads/main)

## step trace (the first missing OK names the culprit)
```text
analyzer OK
```

- failed test cases: 1; failed suites: 4

## FAILED: П39 · твик-журнал с гарантированным откатом.живой реестр: твик -> откат -> reg-экспорт байт-в-байт (только Windows).полный цикл: apply меняет, undo возвращает реестр байт-в-байт
```text

```
```text
at Set-RegistryValueTyped, D:\a\domovoy-tweaker\domovoy-tweaker\tools\Invoke-DomovoyTweakJournal.ps1:169
at Set-TweakNewState, D:\a\domovoy-tweaker\domovoy-tweaker\tools\Invoke-DomovoyTweakJournal.ps1:277
at Invoke-DomovoyTweakJournal, D:\a\domovoy-tweaker\domovoy-tweaker\tools\Invoke-DomovoyTweakJournal.ps1:495
at <ScriptBlock>, D:\a\domovoy-tweaker\domovoy-tweaker\tools\Invoke-DomovoyTweakJournal.ps1:506
at <ScriptBlock>, D:\a\domovoy-tweaker\domovoy-tweaker\tests\Domovoy.V15.TweakJournal.Tests.ps1:258
```

## FAILED SUITE: Pester

## FAILED SUITE: D:\a\domovoy-tweaker\domovoy-tweaker\tests\Domovoy.V15.TweakJournal.Tests.ps1

## FAILED SUITE: П39 · твик-журнал с гарантированным откатом

## FAILED SUITE: П39 · твик-журнал с гарантированным откатом.живой реестр: твик -> откат -> reg-экспорт байт-в-байт (только Windows)

