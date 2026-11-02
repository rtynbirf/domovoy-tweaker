function Get-DomovoySmartScreenStatus {
    <#
    .SYNOPSIS
    Reports the SmartScreen and SMB signing configuration.
    Read-only (catalog #95).

    .DESCRIPTION
    Answers, in one honest table, what the machine's persistent configuration
    says about Microsoft Defender SmartScreen and SMB signing:

    - the Explorer-level SmartScreenEnabled value;
    - the machine policy EnableSmartScreen under HKLM\SOFTWARE\Policies\Microsoft\Windows\System
      (the "Configure Windows Defender SmartScreen" policy, ADMX file
      SmartScreen.admx);
    - the Microsoft Edge policy SmartScreenEnabled under
      HKLM\SOFTWARE\Policies\Microsoft\Edge (REG_DWORD, 0 = off, 1 = on);
    - whether SMB signing is required on the server side (LanManServer
      Parameters) and on the client side (LanManWorkstation Parameters).

    Everything comes from documented registry values via the same safe reader
    the probes use; every read is wrapped in try/catch, and a missing key or
    value is reported as '<unset>' - an honest row, never an error and never
    a guess. SMB signing defaults are stated honestly: starting with
    Windows 11 24H2 (Enterprise/Pro/Education) and Windows Server 2025 SMB
    signing is required by default, so an unset value means the Windows
    default applies, not that signing is off.

    The audit is strictly read-only: no registry writes, no service or task
    changes, no network access (state invariant I4).

    The Explorer-level SmartScreenEnabled string is reported raw. Microsoft
    Learn currently documents the SmartScreen policy values (the machine
    policy and the Edge policy); this function deliberately does not invent
    semantics for the local string beyond whether it is configured.

    .EXAMPLE
    Get-DomovoySmartScreenStatus
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    if (($PSVersionTable.PSVersion.Major -ge 6) -and -not $IsWindows) {
        throw 'Get-DomovoySmartScreenStatus reads the Windows registry: it requires Windows.'
    }

    $explorerKey   = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer'
    $policyKey     = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
    $edgePolicyKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
    $smbServerKey  = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanManServer\Parameters'
    $smbClientKey  = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanManWorkstation\Parameters'

    # Every read goes through the module's safe reader (try/catch inside);
    # a missing key or value comes back as '<unset>', not as an error.
    $explorerValue   = Get-RegistryValueSafe -Path $explorerKey   -Name 'SmartScreenEnabled'
    $policyValue     = Get-RegistryValueSafe -Path $policyKey     -Name 'EnableSmartScreen'
    $edgePolicyValue = Get-RegistryValueSafe -Path $edgePolicyKey -Name 'SmartScreenEnabled'
    $smbServerValue  = Get-RegistryValueSafe -Path $smbServerKey  -Name 'RequireSecuritySignature'
    $smbClientValue  = Get-RegistryValueSafe -Path $smbClientKey  -Name 'RequireSecuritySignature'

    # Honest interpretation, only where the value semantics are documented.
    $policyVerdict = switch ($policyValue) {
        '1'      { 'SmartScreen policy is enabled (Configure Windows Defender SmartScreen)' }
        '0'      { 'SmartScreen policy is disabled' }
        '<unset>' { 'policy not configured - Windows default applies' }
        default  { "raw value '$policyValue' - not interpreted" }
    }
    $edgePolicyVerdict = switch ($edgePolicyValue) {
        '1'      { 'Microsoft Edge SmartScreen policy is enabled' }
        '0'      { 'Microsoft Edge SmartScreen policy is disabled (value 0)' }
        '<unset>' { 'policy not configured - Edge default applies (SmartScreen on by default)' }
        default  { "raw value '$edgePolicyValue' - not interpreted" }
    }
    # The Explorer string has no currently documented value semantics on
    # Microsoft Learn, so it is echoed raw - honesty beats interpretation.
    $explorerVerdict = if ($explorerValue -eq '<unset>') {
        'not set - the Windows default for this setting applies'
    }
    else {
        "configured (raw string '$explorerValue')"
    }
    $smbServerVerdict = switch ($smbServerValue) {
        '1'      { 'SMB signing is required for inbound connections (server side)' }
        '0'      { 'SMB signing is not required for inbound connections (server side)' }
        '<unset>' { 'not configured - Windows default applies' }
        default  { "raw value '$smbServerValue' - not interpreted" }
    }
    $smbClientVerdict = switch ($smbClientValue) {
        '1'      { 'SMB signing is required for outbound connections (client side)' }
        '0'      { 'SMB signing is not required for outbound connections (client side)' }
        '<unset>' { 'not configured - Windows default applies' }
        default  { "raw value '$smbClientValue' - not interpreted" }
    }

    $rows = @(
        [pscustomobject]@{
            Path      = $explorerKey
            ValueName = 'SmartScreenEnabled'
            Value     = $explorerValue
            Verdict   = $explorerVerdict
        },
        [pscustomobject]@{
            Path      = $policyKey
            ValueName = 'EnableSmartScreen'
            Value     = $policyValue
            Verdict   = $policyVerdict
        },
        [pscustomobject]@{
            Path      = $edgePolicyKey
            ValueName = 'SmartScreenEnabled'
            Value     = $edgePolicyValue
            Verdict   = $edgePolicyVerdict
        },
        [pscustomobject]@{
            Path      = $smbServerKey
            ValueName = 'RequireSecuritySignature'
            Value     = $smbServerValue
            Verdict   = $smbServerVerdict
        },
        [pscustomobject]@{
            Path      = $smbClientKey
            ValueName = 'RequireSecuritySignature'
            Value     = $smbClientValue
            Verdict   = $smbClientVerdict
        }
    )

    $configuredCount = @($rows | Where-Object { $_.Value -ne '<unset>' }).Count

    [pscustomobject]@{
        Rows = $rows
        Summary = [pscustomobject]@{
            SettingsAudited                 = @($rows).Count
            ConfiguredValues                = $configuredCount
            SmartScreenPolicyConfigured     = ($policyValue -ne '<unset>')
            EdgeSmartScreenPolicyConfigured = ($edgePolicyValue -ne '<unset>')
            SmbSigningRequiredServer        = ($smbServerValue -eq '1')
            SmbSigningRequiredClient        = ($smbClientValue -eq '1')
            Note = 'Registry configuration only; a missing value is reported as <unset>, never guessed. SMB signing default: Windows 11 24H2 (Enterprise/Pro/Education) and Windows Server 2025 require SMB signing by default; SmbSigningRequired* flags compare the raw value and are false when the value is unset.'
        }
    }
}
