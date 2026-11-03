# CI failure report

- run: 54 on 5201732de9d6771d6da59337bb7caaf5b692afb4 (refs/heads/main)

## step trace (the first missing OK names the culprit)
```text
analyzer OK
```

- failed test cases: 2; failed suites: 5

## FAILED: v0.5 effect reports.change report answers from the ledger with dates
```text

```
```text
at Get-DomovoyStrings, D:\a\domovoy-tweaker\domovoy-tweaker\src\Domovoy\Private\Get-DomovoyStrings.ps1:141
at Get-DomovoyChangeReport, D:\a\domovoy-tweaker\domovoy-tweaker\src\Domovoy\Public\Get-DomovoyChangeReport.ps1:41
at <ScriptBlock>, D:\a\domovoy-tweaker\domovoy-tweaker\tests\Domovoy.Loop.Tests.ps1:456
```

## FAILED: GUI (Show-Domovoy).builds the whole window in preview mode: catalog in, journal status on
```text

```
```text
at Get-DomovoyStrings, D:\a\domovoy-tweaker\domovoy-tweaker\src\Domovoy\Private\Get-DomovoyStrings.ps1:141
at Show-Domovoy, D:\a\domovoy-tweaker\domovoy-tweaker\src\Domovoy\Public\Show-Domovoy.ps1:55
at <ScriptBlock>, D:\a\domovoy-tweaker\domovoy-tweaker\tests\Domovoy.V07.Tests.ps1:624
```

## FAILED SUITE: Pester

## FAILED SUITE: D:\a\domovoy-tweaker\domovoy-tweaker\tests\Domovoy.Loop.Tests.ps1

## FAILED SUITE: v0.5 effect reports

## FAILED SUITE: D:\a\domovoy-tweaker\domovoy-tweaker\tests\Domovoy.V07.Tests.ps1

## FAILED SUITE: GUI (Show-Domovoy)

