function Get-DomovoyPrivilege {
    <#
    .SYNOPSIS
    Lists the privileges of the current process token with their state
    (enabled/disabled) - read only, nothing is changed.

    .DESCRIPTION
    Catalog feature 52, the visible half: the same token privileges Modern
    Tweaker adjusted natively (AdjustTokenPrivileges x5) are shown here as an
    honest table. Enabling and disabling goes through Enable-DomovoyPrivilege
    and Disable-DomovoyPrivilege, and every change is recorded in the ledger.

    .EXAMPLE
    Get-DomovoyPrivilege
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $TOKEN_QUERY = 0x8
    $TokenPrivilegesClass = 3
    $SE_PRIVILEGE_ENABLED = 0x2
    $SE_PRIVILEGE_ENABLED_BY_DEFAULT = 0x1

    $hToken = [IntPtr]::Zero
    if (-not [Domovoy.Native.Token]::OpenProcessToken(
            [Domovoy.Native.Token]::GetCurrentProcess(),
            $TOKEN_QUERY,
            [ref]$hToken)) {
        throw ("OpenProcessToken failed (error {0})." -f [System.Runtime.InteropServices.Marshal]::GetLastWin32Error())
    }

    try {
        $len = [uint32]0
        $null = [Domovoy.Native.Token]::GetTokenInformation(
            $hToken, $TokenPrivilegesClass, [IntPtr]::Zero, 0, [ref]$len)
        if ($len -eq 0) {
            throw 'GetTokenInformation returned an empty buffer size.'
        }

        $buffer = [System.Runtime.InteropServices.Marshal]::AllocHGlobal([int]$len)
        try {
            $null = [Domovoy.Native.Token]::GetTokenInformation(
                $hToken, $TokenPrivilegesClass, $buffer, $len, [ref]$len)
            if (-not $?) {
                throw ("GetTokenInformation failed (error {0})." -f [System.Runtime.InteropServices.Marshal]::GetLastWin32Error())
            }

            $count = [System.Runtime.InteropServices.Marshal]::ReadInt32($buffer, 0)
            $base = [System.IntPtr]::Add($buffer, 4)

            for ($i = 0; $i -lt $count; $i++) {
                $ptr = [System.IntPtr]::Add($base, 12 * $i)
                $item = [System.Runtime.InteropServices.Marshal]::PtrToStructure(
                    $ptr, [type]'Domovoy.Native.Token+DomovoyLuidAndAttributes')

                $name = New-Object System.Text.StringBuilder 256
                $cch = [uint32]256
                if ([Domovoy.Native.Token]::LookupPrivilegeNameW(
                        $null, [ref]$item.Luid, $name, [ref]$cch)) {
                    $enabled = ($item.Attributes -band $SE_PRIVILEGE_ENABLED) -ne 0
                    $byDefault = ($item.Attributes -band $SE_PRIVILEGE_ENABLED_BY_DEFAULT) -ne 0
                    [pscustomobject]@{
                        Name = $name.ToString()
                        State = if ($enabled) { 'Enabled' } else { 'Disabled' }
                        EnabledByDefault = [bool]$byDefault
                    }
                }
            }
        }
        finally {
            [System.Runtime.InteropServices.Marshal]::FreeHGlobal($buffer)
        }
    }
    finally {
        [void][Domovoy.Native.Token]::CloseHandle($hToken)
    }
}
