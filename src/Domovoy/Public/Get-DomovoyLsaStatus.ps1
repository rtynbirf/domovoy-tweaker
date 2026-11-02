function Get-DomovoyLsaStatus {
    <#
    .SYNOPSIS
    Reports the LSA / credential protection registry configuration.
    Read-only (catalog #94).

    .DESCRIPTION
    Answers, in one honest table, what the machine's persistent LSA policy
    says: whether LSASS runs as a protected process (RunAsPPL and its boot
    start companion), whether Credential Guard is configured (LsaCfgFlags
    together with the Device Guard VBS switch), and how NTLM traffic is
    restricted. Everything comes from documented registry values via the
    same safe reader the probes use; a value that is not set is reported as
    '<unset>', never guessed.

    The registry says what the machine is CONFIGURED for. The runtime state
    of LSASS after a reboot can differ - this report deliberately does not
    claim to read kernel state.

    .EXAMPLE
    Get-DomovoyLsaStatus
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $lsaKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
    $dgKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'
    $msvKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0'

    $runAsPpl = Get-RegistryValueSafe -Path $lsaKey -Name 'RunAsPPL'
    $runAsPplBoot = Get-RegistryValueSafe -Path $lsaKey -Name 'RunAsPPLBootStart'
    $lsaCfgFlags = Get-RegistryValueSafe -Path $lsaKey -Name 'LsaCfgFlags'
    $vbsEnabled = Get-RegistryValueSafe -Path $dgKey -Name 'EnableVirtualizationBasedSecurity'
    $ntlmIn = Get-RegistryValueSafe -Path $msvKey -Name 'RestrictReceivingNTLMTraffic'
    $ntlmOut = Get-RegistryValueSafe -Path $msvKey -Name 'RestrictSendingNTLMTraffic'

    # Honest interpretation of the documented value meanings.
    $pplConfigured = ($runAsPpl -eq '1')
    $cgConfigured = ($lsaCfgFlags -eq '1')
    $vbsConfigured = ($vbsEnabled -eq '1')

    [pscustomobject]@{
        RunAsPPL = $runAsPpl
        RunAsPPLBootStart = $runAsPplBoot
        PplConfigured = $pplConfigured
        LsaCfgFlags = $lsaCfgFlags
        EnableVirtualizationBasedSecurity = $vbsEnabled
        CredentialGuardConfigured = ($cgConfigured -and $vbsConfigured)
        RestrictReceivingNTLMTraffic = $ntlmIn
        RestrictSendingNTLMTraffic = $ntlmOut
        Note = 'Registry configuration only; the runtime LSASS state can differ until reboot. Values shown as <unset> are not present.'
    }
}
