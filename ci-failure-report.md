# CI failure report

- run: 91 on cdfc474196671fc8a530ffe3d66f809e5366c48f (refs/heads/main)

## step trace (the first missing OK names the culprit)
```text
analyzer OK
```

testResults.xml is missing - the failing step ran before Pester, or Pester crashed before writing it.
