function Read-DomovoyRegistryPol {
    <#
    .SYNOPSIS
    Parses a Group Policy Registry.pol (PReg) binary file back into records.

    .DESCRIPTION
    The exact inverse of ConvertTo-DomovoyRegistryPol, used as a self-check by
    Export-DomovoyPolicy (the export is only valid when it can be parsed back)
    and by the round-trip tests. REG_DWORD and REG_QWORD data are returned as
    numbers, REG_SZ/REG_EXPAND_SZ as strings (terminating nulls stripped).
    This command never touches the registry - bytes only.

    .PARAMETER Path
    Path to a .pol file.

    .PARAMETER Bytes
    Raw .pol bytes (tests).

    .EXAMPLE
    Read-DomovoyRegistryPol -Path .\Machine-Registry.pol
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(ParameterSetName = 'ByPath')]
        [string]$Path,

        [Parameter(ParameterSetName = 'ByBytes', Mandatory)]
        [byte[]]$Bytes
    )

    if ($PSCmdlet.ParameterSetName -eq 'ByPath') {
        $Bytes = [System.IO.File]::ReadAllBytes($Path)
    }

    if ($Bytes.Length -lt 8) {
        throw 'Registry.pol: file is too short to carry the PReg header.'
    }
    if ($Bytes[0] -ne 0x50 -or $Bytes[1] -ne 0x52 -or $Bytes[2] -ne 0x65 -or $Bytes[3] -ne 0x67) {
        throw 'Registry.pol: bad signature (expected PReg).'
    }
    $version = [BitConverter]::ToUInt32($Bytes, 4)
    if ($version -ne 1) {
        throw ("Registry.pol: unsupported format version {0}." -f $version)
    }

    # Reads one null-terminated UTF-16LE field starting at PosRef.Value,
    # returns the text and advances the position past the terminating null.
    # [ref] is required: a plain scriptblock call would mutate a copy.
    $readField = {
        param([ref]$PosRef)
        $start = $PosRef.Value
        while ($PosRef.Value + 1 -lt $Bytes.Length -and
            [BitConverter]::ToUInt16($Bytes, $PosRef.Value) -ne 0) {
            $PosRef.Value += 2
        }
        if ($PosRef.Value + 1 -ge $Bytes.Length) {
            throw 'Registry.pol: unexpected end of file inside a string field.'
        }
        $text = [System.Text.Encoding]::Unicode.GetString($Bytes, $start, $PosRef.Value - $start)
        $PosRef.Value += 2
        return $text
    }

    $pos = 8
    $posRef = [ref]$pos
    $results = @()

    while ($posRef.Value -lt $Bytes.Length) {
        $at = $posRef.Value
        if ([BitConverter]::ToUInt16($Bytes, $at) -ne 0x5B) {
            throw ("Registry.pol: expected '[' at byte offset {0}." -f $at)
        }
        $posRef.Value += 2

        $key = & $readField $posRef
        if ([BitConverter]::ToUInt16($Bytes, $posRef.Value) -ne 0x3B) {
            throw ("Registry.pol: expected ';' after key at offset {0}." -f $posRef.Value)
        }
        $posRef.Value += 2

        $name = & $readField $posRef
        if ([BitConverter]::ToUInt16($Bytes, $posRef.Value) -ne 0x3B) {
            throw ("Registry.pol: expected ';' after value name at offset {0}." -f $posRef.Value)
        }
        $posRef.Value += 2

        $regType = & $readField $posRef
        if ([BitConverter]::ToUInt16($Bytes, $posRef.Value) -ne 0x3B) {
            throw ("Registry.pol: expected ';' after type at offset {0}." -f $posRef.Value)
        }
        $posRef.Value += 2

        $size = [BitConverter]::ToUInt32($Bytes, $posRef.Value)
        $posRef.Value += 4
        if ([BitConverter]::ToUInt16($Bytes, $posRef.Value) -ne 0x3B) {
            throw ("Registry.pol: expected ';' before data at offset {0}." -f $posRef.Value)
        }
        $posRef.Value += 2

        if ($posRef.Value + $size -gt $Bytes.Length) {
            throw 'Registry.pol: data runs past the end of the file.'
        }
        $data = $null
        switch ($regType) {
            'REG_DWORD' {
                if ($size -ne 4) { throw 'Registry.pol: REG_DWORD data must be 4 bytes.' }
                $data = [BitConverter]::ToUInt32($Bytes, $posRef.Value)
            }
            'REG_QWORD' {
                if ($size -ne 8) { throw 'Registry.pol: REG_QWORD data must be 8 bytes.' }
                $data = [BitConverter]::ToUInt64($Bytes, $posRef.Value)
            }
            'REG_SZ' {
                $data = [System.Text.Encoding]::Unicode.GetString($Bytes, $posRef.Value, $size).TrimEnd([char]0)
            }
            'REG_EXPAND_SZ' {
                $data = [System.Text.Encoding]::Unicode.GetString($Bytes, $posRef.Value, $size).TrimEnd([char]0)
            }
            default {
                throw ("Registry.pol: unsupported registry type '{0}'." -f $regType)
            }
        }
        $posRef.Value += $size

        if ([BitConverter]::ToUInt16($Bytes, $posRef.Value) -ne 0x5D) {
            throw ("Registry.pol: expected ']' after data at offset {0}." -f $posRef.Value)
        }
        $posRef.Value += 2

        $results += [pscustomobject]@{
            KeyPath = $key
            ValueName = $name
            RegType = $regType
            Data = $data
        }
    }

    return $results
}
