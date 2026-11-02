function Invoke-DomovoyGroup {
    <#
    .SYNOPSIS
    Shows the resolved dry-run plan for a feature group (default) or applies
    it in dependency order.

    .DESCRIPTION
    Catalog 102: a group sits on top of profiles. The dependency graph of
    groups is resolved first (depth-first, dependencies before dependents);
    a cycle is an honest error thrown before anything is planned. The
    resolved content of every group - whole profiles and single features -
    is flattened into one ordered plan. Every plan row records WHERE the
    feature came from (direct list, via profile, via a dependency group);
    duplicates are not silently dropped - they are reported as skipped with
    the first source named. Features above the group's maxRisk ceiling and
    features without a manifest are skipped and reported honestly.

    Without -Apply nothing is changed (invariant I3). With -Apply one system
    restore point is created for the whole group and every feature is driven
    through the full feature pipeline (snapshot, probes, journal, undo);
    a failing feature does not abort the package - it is collected in the
    report. The group-level fact (order, counts) is recorded as a
    'group.apply' ledger entry; under -WhatIf nothing is written.

    .PARAMETER Id
    Group id (see Get-DomovoyGroup).

    .PARAMETER Apply
    Apply every resolved feature in dependency order (elevation still
    enforced per feature).

    .PARAMETER SkipRestorePoint
    Skip the single group-level restore point.

    .EXAMPLE
    Invoke-DomovoyGroup -Id home-essentials

    .EXAMPLE
    Invoke-DomovoyGroup -Id home-essentials -Apply
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$Id,

        [switch]$Apply,

        [switch]$SkipRestorePoint
    )

    $resolved = @(Get-DomovoyGroup -Id $Id)
    if ($resolved.Count -eq 0) {
        throw "Group not found: $Id"
    }
    if ($resolved.Count -gt 1) {
        throw ("Multiple groups with id '{0}' found." -f $Id)
    }
    $rootGroup = $resolved[0]

    $groupOrder = @(Get-DomovoyGroupResolutionOrder -RootId $rootGroup.Id)

    # Flatten the ordered groups into raw content rows with attribution.
    $content = @()
    $unresolved = @()
    foreach ($group in $groupOrder) {
        foreach ($profileId in @($group.Profiles)) {
            $profileDef = @(Get-DomovoyProfile -Id $profileId)
            if ($profileDef.Count -eq 0) {
                $unresolved += [pscustomobject]@{
                    Feature = $profileId
                    Group   = $group.Id
                    Reason  = 'profile not found'
                }
                continue
            }
            foreach ($featureId in @($profileDef[0].Features)) {
                $content += [pscustomobject]@{
                    Feature = $featureId
                    Group   = $group.Id
                    Source  = ("profile:{0}" -f $profileId)
                }
            }
        }
        foreach ($featureId in @($group.Features)) {
            $content += [pscustomobject]@{
                Feature = $featureId
                Group   = $group.Id
                Source  = 'features'
            }
        }
    }

    # Deduplicate: the first occurrence wins and its source is the one the
    # later duplicates are honestly reported against.
    $ordered = @()
    $skipped = @($unresolved)
    $seenSource = @{}
    foreach ($item in $content) {
        if ($seenSource.ContainsKey($item.Feature)) {
            $skipped += [pscustomobject]@{
                Feature = $item.Feature
                Group   = $item.Group
                Reason  = ("duplicate - already ordered via {0}" -f $seenSource[$item.Feature])
            }
            continue
        }
        $seenSource[$item.Feature] = $item.Source
        $ordered += $item
    }

    # Filter by the root group's risk ceiling and manifest existence - the
    # same honest skip semantics Invoke-DomovoyProfile uses.
    $riskOrder = @{ low = 0; medium = 1; high = 2 }
    $maxRisk = $riskOrder[$rootGroup.MaxRisk]

    $executable = @()
    foreach ($item in $ordered) {
        $feature = @(Get-DomovoyFeature -Id $item.Feature)
        if ($feature.Count -eq 0) {
            $skipped += [pscustomobject]@{
                Feature = $item.Feature
                Group   = $item.Group
                Reason  = 'manifest not found'
            }
            continue
        }
        if ($riskOrder[$feature[0].Risk] -gt $maxRisk) {
            $skipped += [pscustomobject]@{
                Feature = $item.Feature
                Group   = $item.Group
                Reason  = ("risk '{0}' exceeds group max '{1}'" -f $feature[0].Risk, $rootGroup.MaxRisk)
            }
            continue
        }
        $executable += $item
    }

    $planRows = @()
    $orderNo = 0
    foreach ($item in $executable) {
        $orderNo++
        $planRows += [pscustomobject]@{
            Order   = $orderNo
            Feature = $item.Feature
            Group   = $item.Group
            Source  = $item.Source
        }
    }

    if (-not $Apply) {
        [pscustomobject]@{
            Group   = $rootGroup.Id
            Mode    = 'DryRun'
            MaxRisk = $rootGroup.MaxRisk
            Order   = $planRows
            Skipped = $skipped
        }
        return
    }

    # One restore point for the whole group (not one per feature).
    if (-not $SkipRestorePoint) {
        try {
            New-DomovoyRestorePoint -Description "Domovoy group: $($rootGroup.Id)" -ErrorAction Stop | Out-Null
        }
        catch {
            Write-Verbose ("Restore point was not created: {0}" -f $_.Exception.Message)
        }
    }

    $applied = @()
    $failed = 0
    foreach ($row in $planRows) {
        if (-not $PSCmdlet.ShouldProcess($row.Feature, 'Apply group feature')) {
            continue
        }
        try {
            $applied += Invoke-DomovoyFeature -Id $row.Feature -Apply -SkipRestorePoint
        }
        catch {
            # Honest report: a failing feature is collected, not hidden.
            $failed++
            $applied += [pscustomobject]@{
                Feature         = $row.Feature
                Mode            = 'Apply'
                Error           = $_.Exception.Message
                Verification    = $null
                LedgerTimestamp = $null
            }
        }
    }

    # The group-level fact is recorded even when every feature failed -
    # the counts tell the truth. Under -WhatIf nothing is written.
    if ($PSCmdlet.ShouldProcess($rootGroup.Id, 'Record group.apply ledger entry')) {
        $null = Write-DomovoyLedgerEntry -Entry @{
            event        = 'group.apply'
            groupId      = $rootGroup.Id
            ordered      = @($planRows | ForEach-Object { $_.Feature })
            appliedCount = @($planRows).Count
            skippedCount = @($skipped).Count
            failedCount  = $failed
        }
    }

    [pscustomobject]@{
        Group   = $rootGroup.Id
        Mode    = 'Apply'
        MaxRisk = $rootGroup.MaxRisk
        Order   = $planRows
        Skipped = $skipped
        Applied = $applied
    }
}
