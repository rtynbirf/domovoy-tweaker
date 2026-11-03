# CI failure report

- run: 79 on 805ae8a2e33195f38ddadec694bf3937230dc758 (refs/heads/main)

## step trace (the first missing OK names the culprit)
```text
analyzer OK
```

- failed test cases: 1; failed suites: 3

## FAILED: GUI (Show-Domovoy).click handlers resolve the private string table through the module-bound bridge (v1.5.4 portable-exe regression)
```text

```
```text
at $form.Tag.Output.Text | Should -Match ([regex]::Escape($expectedSelect)), D:\a\domovoy-tweaker\domovoy-tweaker\tests\Domovoy.V07.Tests.ps1:674
at <ScriptBlock>, D:\a\domovoy-tweaker\domovoy-tweaker\tests\Domovoy.V07.Tests.ps1:674
```

## FAILED SUITE: Pester

## FAILED SUITE: D:\a\domovoy-tweaker\domovoy-tweaker\tests\Domovoy.V07.Tests.ps1

## FAILED SUITE: GUI (Show-Domovoy)

