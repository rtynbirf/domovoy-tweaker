# Token privilege P/Invoke for the Domovoy.Native.Token type (loaded once).
# Used by Get/Enable/Disable-DomovoyPrivilege: the same native power Modern
# Tweaker used (AdjustTokenPrivileges), but every change goes through a
# journaled, visible command (catalog 52).

if (-not ([System.Management.Automation.PSTypeName]'Domovoy.Native.Token').Type) {
    Add-Type -Namespace Domovoy.Native -Name Token -MemberDefinition @'
[System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
public struct DomovoyLuid { public uint LowPart; public int HighPart; }

[System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
public struct DomovoyLuidAndAttributes { public DomovoyLuid Luid; public uint Attributes; }

[System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
public struct DomovoyTokenPrivileges1 { public uint PrivilegeCount; public DomovoyLuid Luid; public uint Attributes; }

[System.Runtime.InteropServices.DllImport("advapi32.dll", SetLastError = true)]
public static extern bool OpenProcessToken(System.IntPtr ProcessHandle, uint DesiredAccess, out System.IntPtr TokenHandle);

[System.Runtime.InteropServices.DllImport("advapi32.dll", SetLastError = true, CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
public static extern bool LookupPrivilegeNameW(string lpSystemName, ref DomovoyLuid lpLuid, System.Text.StringBuilder lpName, ref uint cchName);

[System.Runtime.InteropServices.DllImport("advapi32.dll", SetLastError = true, CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
public static extern bool LookupPrivilegeValueW(string lpSystemName, string lpName, out DomovoyLuid lpLuid);

[System.Runtime.InteropServices.DllImport("advapi32.dll", SetLastError = true)]
public static extern bool AdjustTokenPrivileges(System.IntPtr TokenHandle, bool DisableAllPrivileges, ref DomovoyTokenPrivileges1 NewState, uint BufferLength, System.IntPtr PreviousState, System.IntPtr ReturnLength);

[System.Runtime.InteropServices.DllImport("advapi32.dll", SetLastError = true)]
public static extern bool GetTokenInformation(System.IntPtr TokenHandle, uint TokenInformationClass, System.IntPtr TokenInformation, uint TokenInformationLength, out uint ReturnLength);

[System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError = true)]
public static extern System.IntPtr GetCurrentProcess();

[System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError = true)]
public static extern bool CloseHandle(System.IntPtr hObject);
'@
}

function Set-DomovoyTokenPrivilege {
    <#
    .SYNOPSIS
    Enables or disables one named privilege in the current process token.
    Returns the previous state so callers can journal it.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [bool]$Enable
    )

    $TOKEN_ADJUST_PRIVILEGES = 0x20
    $TOKEN_QUERY = 0x8
    $ERROR_NOT_ALL_ASSIGNED = 1300

    $hToken = [IntPtr]::Zero
    if (-not [Domovoy.Native.Token]::OpenProcessToken(
            [Domovoy.Native.Token]::GetCurrentProcess(),
            ($TOKEN_ADJUST_PRIVILEGES -bor $TOKEN_QUERY),
            [ref]$hToken)) {
        throw ("OpenProcessToken failed (error {0})." -f [System.Runtime.InteropServices.Marshal]::GetLastWin32Error())
    }

    try {
        $luid = New-Object 'Domovoy.Native.Token+DomovoyLuid'
        if (-not [Domovoy.Native.Token]::LookupPrivilegeValueW($null, $Name, [ref]$luid)) {
            throw ("Unknown privilege name: {0}" -f $Name)
        }

        $previous = 'Disabled'
        foreach ($priv in @(Get-DomovoyPrivilege)) {
            if ($priv.Name -eq $Name) { $previous = $priv.State }
        }

        # Single-privilege TOKEN_PRIVILEGES, flattened (count + luid + attrs).
        $tp = New-Object 'Domovoy.Native.Token+DomovoyTokenPrivileges1'
        $tp.PrivilegeCount = 1
        $tp.Luid = $luid
        $tp.Attributes = if ($Enable) { 0x2 } else { 0 }

        $ok = [Domovoy.Native.Token]::AdjustTokenPrivileges($hToken, $false, [ref]$tp, 0, [IntPtr]::Zero, [IntPtr]::Zero)
        if (-not $ok) {
            throw ("AdjustTokenPrivileges failed (error {0})." -f [System.Runtime.InteropServices.Marshal]::GetLastWin32Error())
        }
        $err = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
        if ($err -eq $ERROR_NOT_ALL_ASSIGNED) {
            throw ("The privilege is not held by this process token: {0}" -f $Name)
        }
        if ($err -ne 0) {
            throw ("AdjustTokenPrivileges did not fully succeed (error {0})." -f $err)
        }

        return @{ Name = $Name; Enable = $Enable; PreviousState = $previous }
    }
    finally {
        [void][Domovoy.Native.Token]::CloseHandle($hToken)
    }
}
