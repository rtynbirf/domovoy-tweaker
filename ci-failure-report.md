# CI failure report

- run: 77 on 19eb75df4e6ea3557ff16790baf97e21b682f8c9 (refs/heads/main)

## step trace (the first missing OK names the culprit)
```text
analyzer OK
```

- failed test cases: 1; failed suites: 3

## FAILED: GUI (Show-Domovoy).click handlers resolve the private string table through the module-bound bridge (v1.5.4 portable-exe regression)
```text

```
```text
at $form.Tag.Output.Text | Should -Match ([regex]::Escape($expectedSelect)), D:\a\domovoy-tweaker\domovoy-tweaker\tests\Domovoy.V07.Tests.ps1:661
at <ScriptBlock>, D:\a\domovoy-tweaker\domovoy-tweaker\tests\Domovoy.V07.Tests.ps1:661
```

## FAILED SUITE: Pester

## FAILED SUITE: D:\a\domovoy-tweaker\domovoy-tweaker\tests\Domovoy.V07.Tests.ps1

## FAILED SUITE: GUI (Show-Domovoy)

