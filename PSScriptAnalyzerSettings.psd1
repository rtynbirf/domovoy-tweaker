# PSScriptAnalyzer settings for the Domovoy module (repo root).
#
# Severity policy:
#   - CI fails on Error severity findings.
#   - Warnings are reported in the CI log but are non-blocking.
#   - Rules listed in ExcludeRules below demonstrably fire on src/ today and
#     are accepted noise; each one carries a one-line reason.
#
# Calibration: Invoke-ScriptAnalyzer was run against src/ with
# PSScriptAnalyzer 1.25.0. Warning-severity rules that fire today:
#   PSAvoidAssignmentToAutomaticVariable          (4 findings)
#   PSAvoidUsingEmptyCatchBlock                   (10 findings)
#   PSReviewUnusedParameter                       (1 finding)
#   PSUseShouldProcessForStateChangingFunctions   (2 findings)
#   PSUseSingularNouns                            (1 finding)
# PSAvoidUsingWriteHost was checked and does NOT fire: the module source
# contains no Write-Host calls at all, so there is nothing to exclude for it.

@{
    # IncludeDefaultRules = $true (v1.4 item 3): run the full default ruleset;
    # only the rules explicitly listed below are silenced.
    IncludeDefaultRules = $true

    ExcludeRules = @(
        # A parameter named $Event is part of the frozen v1.x public API of
        # the ledger undo functions; renaming it would break callers.
        'PSAvoidAssignmentToAutomaticVariable',

        # Empty catch blocks are deliberate best-effort probes in read-only
        # report code (network/shell-menu/GUI sections that must skip absent
        # optional cmdlets silently instead of lying in the report).
        'PSAvoidUsingEmptyCatchBlock',

        # A private helper keeps an unused parameter for signature uniformity
        # with its sibling functions; harmless inside a private function.
        'PSReviewUnusedParameter',

        # Private helpers (Set-DomovoyTimestamp, Set-DomovoyTokenPrivilege) run
        # inside public cmdlets that own SupportsShouldProcess and dry-run at
        # the pipeline level; ShouldProcess on the internals would duplicate
        # the decision points.
        'PSUseShouldProcessForStateChangingFunctions',

        # Get-DomovoyDnsTargets returns several targets by design; renaming a
        # private helper for grammar is churn without value.
        'PSUseSingularNouns'
    )
}
