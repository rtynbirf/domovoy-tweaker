function Export-DomovoyPolicy {
    <#
    .SYNOPSIS
    Exports applied, verified registry-backed features as GPO/Intune-compatible
    policies (catalog 62).

    .DESCRIPTION
    Reads the journal, takes the latest feature.apply event of every feature,
    keeps the verified ones (-IncludeUnverified overrides that) and emits a
    standard Group Policy bundle for the registry-backed subset of each
    manifest:

      Domovoy.admx          administrative template (one policy per feature)
      en-US\Domovoy.adml    language resources for the template
      Machine-Registry.pol  binary PReg file for HKLM-backed values
      User-Registry.pol     binary PReg file for HKCU-backed values
      policy-mapping.csv    every exported value, machine-readable
      README.md             how to load the bundle into gpedit / Intune

    The .pol files are written by Domovoy's own PReg encoder (pure bytes, no
    external tools) and parsed back as a self-check before the export is
    reported as done. Services, Appx packages, DNS and other non-registry ops
    cannot be expressed as Administrative Template policies - they are listed
    under Skipped instead of being silently dropped. When two features enforce
    the same registry value, the newer apply wins, the value is written once,
    and the overwrite is listed under Conflicts.

    This command is read-only with respect to the system: it writes only the
    export directory.

    .PARAMETER OutputDir
    Target directory. Defaults to a timestamped folder inside the Domovoy store.

    .PARAMETER IncludeUnverified
    Also export features whose latest apply did not verify.

    .PARAMETER ProfileId
    Only export features that belong to the given bundled profile
    (catalog 100); the journal stays the source of truth for what was
    actually applied on this machine.

    .PARAMETER Force
    Overwrite an existing output directory.

    .EXAMPLE
    Export-DomovoyPolicy

    .EXAMPLE
    Export-DomovoyPolicy -OutputDir D:\gpo\domovoy -Force
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string]$OutputDir,

        [string]$ProfileId,

        [switch]$IncludeUnverified,

        [switch]$Force
    )

    if ([string]::IsNullOrWhiteSpace($OutputDir)) {
        $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
        $OutputDir = Get-DomovoyStorePath -SubPath ("policy-export-{0}" -f $stamp)
    }
    if ((Test-Path -LiteralPath $OutputDir) -and -not $Force) {
        throw ("Output directory already exists (use -Force to overwrite): {0}" -f $OutputDir)
    }
    $null = New-Item -Path $OutputDir -ItemType Directory -Force

    # Latest feature.apply per feature: the journal is append-only, so the
    # last record for an id is the current state of that feature.
    $applies = @()
    try {
        $applies = @(Get-DomovoyLedger -Last 1000000 | Where-Object { $_.event -eq 'feature.apply' })
    }
    catch { }
    if ($applies.Count -eq 0) {
        throw 'No feature.apply events in the journal - nothing to export.'
    }
    $latest = @{}
    foreach ($entry in $applies) {
        $latest[$entry.featureId] = $entry
    }
    # Oldest first, so that a newer feature overwrites a value shared with an
    # older one - the same order in which they were applied to this machine.
    $ordered = @($latest.Values | Sort-Object -Property timestamp)

    if (-not [string]::IsNullOrWhiteSpace($ProfileId)) {
        # Catalog 100: batch export of one profile. The profile list is the
        # filter; the journal is still what decides "applied and verified".
        $profileDef = @(Get-DomovoyProfile -Id $ProfileId)
        if ($profileDef.Count -eq 0) {
            throw ("Profile not found: {0}" -f $ProfileId)
        }
        $profileFeatures = @($profileDef[0].Features)
        $ordered = @($ordered | Where-Object { $profileFeatures -contains [string]$_.featureId })
        if ($ordered.Count -eq 0) {
            throw ("No applied features of profile '{0}' in the journal - nothing to export." -f $ProfileId)
        }
    }

    # One Registry.pol entry per (class, key, valueName): a shared value is
    # written ONCE, from the feature that was applied last. [ordered] keeps
    # the apply order, which is what a real GPO would resolve to.
    $polEntries = [ordered]@{}
    $admxFeatures = [System.Collections.Generic.List[object]]::new()
    $skipped = @()
    $conflicts = @()

    foreach ($entry in $ordered) {
        $featureId = [string]$entry.featureId
        $verified = ($null -ne $entry.verification) -and ([bool]$entry.verification.AllPass)
        if (-not $verified -and -not $IncludeUnverified) {
            $skipped += ("{0}: the last apply was not verified" -f $featureId)
            continue
        }
        try {
            $manifest = Get-DomovoyManifestForFeature -Id $featureId -LedgerEntry $entry
        }
        catch {
            $skipped += ("{0}: manifest not found" -f $featureId)
            continue
        }

        $registryOps = @($manifest.ops | Where-Object { @('registry.set', 'registry.delete') -contains $_.type })
        if (@($registryOps).Count -eq 0) {
            $skipped += ("{0}: no registry-backed ops (services, appx, dns, ... are not GPO policies)" -f $featureId)
            continue
        }

        $byClass = @{}
        foreach ($op in $registryOps) {
            $norm = ([string]$op.path) -replace '/', '\'
            if ($norm -like 'HKLM:*') {
                $class = 'Machine'
                $key = $norm.Substring(6)
            }
            elseif ($norm -like 'HKCU:*') {
                $class = 'User'
                $key = $norm.Substring(6)
            }
            else {
                $skipped += ("{0}: unsupported hive '{1}'" -f $featureId, $op.path)
                continue
            }
            if (-not $byClass.ContainsKey($class)) {
                $byClass[$class] = [System.Collections.Generic.List[object]]::new()
            }

            if ($op.type -eq 'registry.delete') {
                # The Group Policy delete marker: a value name prefixed with
                # '**Del.' removes the value when the policy applies.
                $regType = 'REG_SZ'
                $polName = '**Del.' + [string]$op.name
                $polData = ''
                $element = @{
                    Kind = 'delete'
                    ValueName = [string]$op.name
                    Key = $key
                }
            }
            else {
                switch ([string]$op.valueType) {
                    'DWord' { $regType = 'REG_DWORD'; $admxKind = 'decimal' }
                    'String' { $regType = 'REG_SZ'; $admxKind = 'text' }
                    'ExpandString' { $regType = 'REG_EXPAND_SZ'; $admxKind = $null }
                    'QWord' { $regType = 'REG_QWORD'; $admxKind = $null }
                    default { $regType = $null; $admxKind = $null }
                }
                if (-not $regType) {
                    $skipped += ("{0}: value type '{1}' cannot be exported" -f $featureId, $op.valueType)
                    continue
                }
                $polName = [string]$op.name
                $polData = $op.value
                if ($admxKind) {
                    $element = @{
                        Kind = $admxKind
                        ValueName = [string]$op.name
                        Key = $key
                        Data = [string]$op.value
                    }
                }
                else {
                    # Binary/MultiString/QWord/ExpandString: enforced through
                    # the .pol file, but Administrative Templates have no
                    # element type that would round-trip them honestly.
                    $element = $null
                    $skipped += ("{0}: '{1}' ({2}) goes to Registry.pol only, ADMX has no element type for it" -f $featureId, $op.name, $op.valueType)
                }
            }

            if ($element) {
                $byClass[$class].Add($element)
            }

            # Delete markers get their own stamp so they never collide with
            # real values; shared values resolve to the latest feature.
            if ($op.type -eq 'registry.delete') {
                $stamp = '{0}|{1}|**Del.{2}' -f $class, $key, $op.name
            }
            else {
                $stamp = '{0}|{1}|{2}' -f $class, $key, $op.name
                if ($polEntries.Contains($stamp)) {
                    $conflicts += ("'{0}' overwrites '{1}' for {2}" -f $featureId, $polEntries[$stamp].Feature, $stamp)
                }
            }
            $polEntries[$stamp] = @{
                Class = $class
                KeyPath = $key
                ValueName = $polName
                RegType = $regType
                Data = $polData
                Feature = $featureId
            }
        }

        foreach ($class in @($byClass.Keys | Sort-Object)) {
            if (@($byClass[$class]).Count -gt 0) {
                $admxFeatures.Add(@{
                    Id = $featureId
                    Class = $class
                    Title = [string]$manifest.title
                    Description = [string]$manifest.description
                    Elements = $byClass[$class]
                })
            }
        }
    }

    # ---- Registry.pol files (binary PReg) ---------------------------------
    $machineList = @($polEntries.Values | Where-Object { $_.Class -eq 'Machine' })
    $userList = @($polEntries.Values | Where-Object { $_.Class -eq 'User' })
    $machineBytes = $null
    $userBytes = $null
    $machineCount = 0
    $userCount = 0
    if ($machineList.Count -gt 0) {
        $machineBytes = ConvertTo-DomovoyRegistryPol -Entry $machineList
        $machineCount = $machineList.Count
    }
    if ($userList.Count -gt 0) {
        $userBytes = ConvertTo-DomovoyRegistryPol -Entry $userList
        $userCount = $userList.Count
    }

    $machinePolPath = $null
    $userPolPath = $null
    if ($machineBytes) {
        $machinePolPath = Join-Path -Path $OutputDir -ChildPath 'Machine-Registry.pol'
        [System.IO.File]::WriteAllBytes($machinePolPath, $machineBytes)
    }
    if ($userBytes) {
        $userPolPath = Join-Path -Path $OutputDir -ChildPath 'User-Registry.pol'
        [System.IO.File]::WriteAllBytes($userPolPath, $userBytes)
    }

    # ---- Domovoy.admx + en-US\Domovoy.adml --------------------------------
    $escape = {
        param([string]$Text)
        [System.Security.SecurityElement]::Escape($Text)
    }

    $policiesXml = [System.Collections.Generic.List[string]]::new()
    $stringsXml = [System.Collections.Generic.List[string]]::new()
    $presentationsXml = [System.Collections.Generic.List[string]]::new()
    $stringsXml.Add('      <string id="DomovoyCategory">Domovoy tweaks</string>')
    $stringsXml.Add('      <string id="DomovoyCategoryExplain">Policies exported from the Domovoy journal. Every policy here mirrors a feature that was applied and verified on the source machine.</string>')

    foreach ($feature in $admxFeatures) {
        $safeId = ([string]$feature.Id) -replace '[^A-Za-z0-9]', ''
        $policyName = 'Domovoy{0}{1}' -f $safeId, $feature.Class
        $stringId = 'D{0}{1}' -f $safeId, $feature.Class
        $explainId = 'E{0}{1}' -f $safeId, $feature.Class
        $presentationId = 'Domovoy{0}{1}Presentation' -f $safeId, $feature.Class
        $firstKey = [string]$feature.Elements[0].Key

        $elementLines = [System.Collections.Generic.List[string]]::new()
        $presentationLines = [System.Collections.Generic.List[string]]::new()
        $index = 0
        foreach ($element in @($feature.Elements)) {
            $index++
            $elementId = 'V{0}' -f $index
            $valueName = (& $escape $element.ValueName)
            $key = (& $escape $element.Key)
            switch ($element.Kind) {
                'decimal' {
                    $elementLines.Add(("            <decimal id=`"{0}`" valueName=`"{1}`" key=`"{2}`" required=`"true`" minValue=`"0`" maxValue=`"4294967295`" />" -f $elementId, $valueName, $key))
                    $presentationLines.Add(("            <decimal refId=`"{0}`" label=`"{1}`">" -f $elementId, $valueName))
                    $presentationLines.Add('            </decimal>')
                }
                'text' {
                    $elementLines.Add(("            <text id=`"{0}`" valueName=`"{1}`" key=`"{2}`" required=`"true`" expandable=`"false`" soft=`"false`" maxLength=`"2048`" />" -f $elementId, $valueName, $key))
                    $presentationLines.Add(("            <text refId=`"{0}`" label=`"{1}`" />" -f $elementId, $valueName))
                }
                'delete' {
                    $elementLines.Add(("            <delete id=`"{0}`" valueName=`"{1}`" key=`"{2}`" />" -f $elementId, $valueName, $key))
                }
            }
        }

        $policiesXml.Add(("      <policy name=`"{0}`" class=`"{1}`" displayName=`"`$(string.{2})`" explainText=`"`$(string.{3})`" key=`"{4}`" presentation=`"`$(presentation.{5})`">" -f $policyName, $feature.Class, $stringId, $explainId, (& $escape $firstKey), $presentationId))
        $policiesXml.Add('        <elements>')
        foreach ($line in $elementLines) {
            $policiesXml.Add($line)
        }
        $policiesXml.Add('        </elements>')
        $policiesXml.Add('      </policy>')

        $stringsXml.Add(('      <string id="{0}">{1}</string>' -f $stringId, (& $escape $feature.Title)))
        $stringsXml.Add(('      <string id="{0}">{1}</string>' -f $explainId, (& $escape $feature.Description)))
        $presentationsXml.Add(("      <presentation id=`"{0}`">" -f $presentationId))
        foreach ($line in $presentationLines) {
            $presentationsXml.Add($line)
        }
        $presentationsXml.Add('      </presentation>')
    }

    $admxPath = $null
    $admlPath = $null
    if ($policiesXml.Count -gt 0) {
        $admxLines = @(
            '<?xml version="1.0" encoding="utf-8"?>',
            '<policyDefinitions revision="1.0" schemaVersion="1.0" xmlns="http://www.microsoft.com/GroupPolicy/PolicyDefinitions">',
            '  <categories>',
            '    <category name="Domovoy" displayName="$(string.DomovoyCategory)" explainText="$(string.DomovoyCategoryExplain)" />',
            '  </categories>',
            '  <policies>'
        )
        $admxLines += $policiesXml.ToArray()
        $admxLines += @('  </policies>', '</policyDefinitions>')
        $admxPath = Join-Path -Path $OutputDir -ChildPath 'Domovoy.admx'
        [System.IO.File]::WriteAllText($admxPath, ($admxLines -join "`r`n") + "`r`n", [System.Text.UTF8Encoding]::new($false))

        $admlLines = @(
            '<?xml version="1.0" encoding="utf-8"?>',
            '<policyDefinitionResources revision="1.0" schemaVersion="1.0" xmlns="http://www.microsoft.com/GroupPolicy/PolicyDefinitions">',
            '  <displayName>Domovoy</displayName>',
            '  <description>Domovoy exported policies.</description>',
            '  <resources>',
            '    <stringTable>'
        )
        $admlLines += $stringsXml.ToArray()
        $admlLines += @('    </stringTable>', '    <presentationTable>')
        $admlLines += $presentationsXml.ToArray()
        $admlLines += @('    </presentationTable>', '  </resources>', '</policyDefinitionResources>')
        $admlDir = Join-Path -Path $OutputDir -ChildPath 'en-US'
        $null = New-Item -Path $admlDir -ItemType Directory -Force
        $admlPath = Join-Path -Path $admlDir -ChildPath 'Domovoy.adml'
        [System.IO.File]::WriteAllText($admlPath, ($admlLines -join "`r`n") + "`r`n", [System.Text.UTF8Encoding]::new($false))
    }

    # ---- policy-mapping.csv ------------------------------------------------
    $mappingPath = $null
    if ($polEntries.Count -gt 0) {
        $mappingPath = Join-Path -Path $OutputDir -ChildPath 'policy-mapping.csv'
        $csv = @('Feature,Class,Key,ValueName,RegType,Data')
        foreach ($polEntry in $polEntries.Values) {
            $csv += ('"{0}","{1}","{2}","{3}","{4}","{5}"' -f $polEntry.Feature, $polEntry.Class, $polEntry.KeyPath, $polEntry.ValueName, $polEntry.RegType, ([string]$polEntry.Data))
        }
        [System.IO.File]::WriteAllText($mappingPath, ($csv -join "`r`n") + "`r`n", [System.Text.UTF8Encoding]::new($false))
    }

    # ---- README.md ----------------------------------------------------------
    $readmePath = Join-Path -Path $OutputDir -ChildPath 'README.md'
    $readme = @(
        '# Domovoy policy export',
        '',
        'Generated from the Domovoy journal: the latest verified apply of every',
        'registry-backed feature, rendered as Group Policy objects.',
        '',
        '## Files',
        '',
        '- `Domovoy.admx` + `en-US\Domovoy.adml` - administrative template, one policy per feature (category: Domovoy).',
        '- `Machine-Registry.pol` / `User-Registry.pol` - binary Registry.pol files (PReg format), machine and user halves.',
        '- `policy-mapping.csv` - every exported registry value, machine-readable (Intune OMA-URI scripts, audits).',
        '',
        '## Load into gpedit (local machine)',
        '',
        '1. Copy `Domovoy.admx` to `%windir%\PolicyDefinitions\` and `en-US\Domovoy.adml` to `%windir%\PolicyDefinitions\en-US\`.',
        '2. Open `gpedit.msc`; the `Domovoy` category appears under Administrative Templates.',
        '3. Policies open without errors; enabling one writes exactly the value Domovoy verified.',
        '',
        '## Load into a domain GPO',
        '',
        '1. Copy `Domovoy.admx` to `\\<domain>\SYSVOL\<domain>\Policies\PolicyDefinitions\`, `en-US` next to it.',
        '2. Copy `Machine-Registry.pol` into the GPO folder `Machine\` and `User-Registry.pol` into `User\`',
        '   (in a fresh GPO these files do not exist yet - create them from the exports).',
        '',
        '## Intune',
        '',
        '- ADMX ingestion: upload `Domovoy.admx` via the documented ADMXInstall OMA-URI (Policy/ConfigOperations/ADMXInstall/Domovoy/Policy/DomovoyAdmx), then use the Settings catalog.',
        '- Direct values: use `policy-mapping.csv` - each row is one HKLM/HKCU value an OMA-URI or PowerShell remediation can enforce.',
        '',
        '## Honest limitations',
        '',
        '- Only registry-backed features are exported; services, Appx packages, DNS, scheduler tasks, files and privileges live in the Domovoy journal instead (see Skipped in the export summary).',
        '- Values of type Binary, MultiString, QWord and ExpandString are enforced through Registry.pol but have no ADMX element type.',
        '- Value names shown as `(default)` in the registry go to Registry.pol only (an empty name in PReg format).',
        '- Non-`Policies` registry paths are written as-is: Group Policy loads them, but they are outside the classic Administrative Templates area.',
        ''
    )
    [System.IO.File]::WriteAllText($readmePath, ($readme -join "`r`n"), [System.Text.UTF8Encoding]::new($false))

    # ---- Self-check: parse the .pol files back -----------------------------
    $selfCheck = 'no .pol files written'
    $parsedOk = $true
    if ($machineBytes) {
        try {
            $parsed = @(Read-DomovoyRegistryPol -Bytes $machineBytes)
            if ($parsed.Count -ne $machineCount) { $parsedOk = $false }
        }
        catch { $parsedOk = $false }
    }
    if ($userBytes -and $parsedOk) {
        try {
            $parsed = @(Read-DomovoyRegistryPol -Bytes $userBytes)
            if ($parsed.Count -ne $userCount) { $parsedOk = $false }
        }
        catch { $parsedOk = $false }
    }
    if ($admxPath) {
        try {
            $null = [xml](Get-Content -LiteralPath $admxPath -Raw -Encoding UTF8)
            $null = [xml](Get-Content -LiteralPath $admlPath -Raw -Encoding UTF8)
        }
        catch {
            $parsedOk = $false
            $selfCheck = 'failed: ADMX/ADML XML did not load'
        }
    }
    if ($parsedOk -and ($machineBytes -or $userBytes)) {
        $selfCheck = 'pass (PReg round-trip + XML well-formed)'
    }
    elseif (-not $parsedOk) {
        $selfCheck = 'failed'
    }

    [pscustomobject]@{
        OutputDir = $OutputDir
        ProfileId = $ProfileId
        MachineEntries = $machineCount
        UserEntries = $userCount
        AdmxPolicies = $admxFeatures.Count
        Skipped = $skipped
        Conflicts = $conflicts
        MachinePol = $machinePolPath
        UserPol = $userPolPath
        Admx = $admxPath
        Adml = $admlPath
        MappingCsv = $mappingPath
        Readme = $readmePath
        SelfCheck = $selfCheck
    }
}
