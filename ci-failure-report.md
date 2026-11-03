# CI failure report

- run: 84 on 73545d8707884ca2518ce70fca2c02fc6a0af13b (refs/tags/v1.6.0)

## step trace (the first missing OK names the culprit)
```text
analyzer OK
```

- failed test cases: 1; failed suites: 3

## FAILED: GUI (Show-Domovoy).runs a catalog action through the background worker to done (v1.6.0 async surface)
```text

```
```text
at $tag.State.busy | Should -BeTrue, D:\a\domovoy-tweaker\domovoy-tweaker\tests\Domovoy.V07.Tests.ps1:707
at <ScriptBlock>, D:\a\domovoy-tweaker\domovoy-tweaker\tests\Domovoy.V07.Tests.ps1:707
```

## FAILED SUITE: Pester

## FAILED SUITE: D:\a\domovoy-tweaker\domovoy-tweaker\tests\Domovoy.V07.Tests.ps1

## FAILED SUITE: GUI (Show-Domovoy)

