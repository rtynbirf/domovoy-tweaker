function ConvertTo-DomovoyRegistryPol {
    <#
    .SYNOPSIS
    Builds the binary content of a Group Policy Registry.pol (PReg) file.

    .DESCRIPTION
    Pure byte work - no registry access, no external tools. The caller decides
    which policy class (Machine/User) an entry belongs to; one .pol file per
    class is written separately, exactly as a real GPO stores them.

    Format (documented in MS-RGPO / "Registry.pol"): 8-byte header
    'PReg' + u32 version 1, then records:
      '[' key ';' valueName ';' type ';' u32le size ';' data ']'
    Key, valueName and type are null-terminated UTF-16LE strings; the bracket
    and semicolon delimiters are UTF-16LE characters too.

    .PARAMETER Entry
    Records with KeyPath (relative to the policy root, e.g. 'SOFTWARE\Policies\...'),
    ValueName ('' means the default value), RegType ('REG_DWORD', 'REG_QWORD',
    'REG_SZ', 'REG_EXPAND_SZ') and Data. A ValueName starting with '**Del.'
    marks a value deletion (Group Policy delete marker).

    .EXAMPLE
    ConvertTo-DomovoyRegistryPol -Entry @{ KeyPath = 'SOFTWARE\X'; ValueName = 'V'; RegType = 'REG_DWORD'; Data = 0 }
    #>
    [CmdletBinding()]
    [OutputType([byte[]])]
    param(
        [Parameter(Mandatory)]
        [object[]]$Entry
    )

    $unicode = [System.Text.Encoding]::Unicode
    $bytes = [System.Collections.Generic.List[byte]]::new()
    $bytes.AddRange([byte[]](0x50, 0x52, 0x65, 0x67, 0x01, 0x00, 0x00, 0x00))

    foreach ($item in @($Entry)) {
        $type = [string]$item.RegType
        switch ($type) {
            'REG_DWORD' {
                $dataBytes = [BitConverter]::GetBytes([uint32]$item.Data)
            }
            'REG_QWORD' {
                $dataBytes = [BitConverter]::GetBytes([uint64]$item.Data)
            }
            'REG_SZ' {
                $dataBytes = $unicode.GetBytes(([string]$item.Data) + [char]0)
            }
            'REG_EXPAND_SZ' {
                $dataBytes = $unicode.GetBytes(([string]$item.Data) + [char]0)
            }
            default {
                throw ("Unsupported registry type for Registry.pol: {0}" -f $type)
            }
        }

        # String fields are UTF-16LE with a terminating null.
        $keyField = $unicode.GetBytes(([string]$item.KeyPath) + [char]0)
        $nameField = $unicode.GetBytes(([string]$item.ValueName) + [char]0)
        $typeField = $unicode.GetBytes($type + [char]0)

        $bytes.AddRange([byte[]](0x5B, 0x00))          # '['
        $bytes.AddRange($keyField)                     # key
        $bytes.AddRange([byte[]](0x3B, 0x00))          # ';'
        $bytes.AddRange($nameField)                    # value name
        $bytes.AddRange([byte[]](0x3B, 0x00))          # ';'
        $bytes.AddRange($typeField)                    # type
        $bytes.AddRange([byte[]](0x3B, 0x00))          # ';'
        $bytes.AddRange([BitConverter]::GetBytes([uint32]$dataBytes.Length))
        $bytes.AddRange([byte[]](0x3B, 0x00))          # ';'
        $bytes.AddRange($dataBytes)                    # data
        $bytes.AddRange([byte[]](0x5D, 0x00))          # ']'
    }

    return $bytes.ToArray()
}
