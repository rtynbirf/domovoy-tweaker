function ConvertTo-DomovoyCab {
    <#
    .SYNOPSIS
    Packs a directory into a single .cab archive via makecab.exe (diamond
    directive), preserving the relative file layout.

    .NOTES
    Used by Invoke-DomovoyDriverDedup: the full third-party driver backup
    must exist as one archive before any old duplicate is removed
    (catalog 43). Throws when makecab reports a non-zero exit code.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$SourceDirectory,

        [Parameter(Mandatory)]
        [string]$DestinationFile
    )

    $sourceRoot = (Get-Item -LiteralPath $SourceDirectory).FullName
    $destFull = [System.IO.Path]::GetFullPath($DestinationFile)
    $destDir = Split-Path -Parent $destFull
    $cabName = Split-Path -Leaf $destFull
    $null = New-Item -ItemType Directory -Path $destDir -Force

    $ddfPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath (
        "domovoy-" + [guid]::NewGuid().ToString('N') + ".ddf")

    $lines = @(
        '.OPTION EXPLICIT',
        '.Set Cabinet=ON',
        '.Set Compress=ON',
        '.Set CompressionType=LZX',
        ('.Set CabinetNameTemplate={0}' -f $cabName),
        ('.Set DiskDirectory1={0}' -f $destDir),
        ('.Set SourceDir={0}' -f $sourceRoot)
    )
    foreach ($file in @(Get-ChildItem -LiteralPath $SourceDirectory -Recurse -File)) {
        $relative = $file.FullName.Substring($sourceRoot.Length).TrimStart('\')
        $lines += ('"{0}"' -f $relative)
    }
    Set-Content -LiteralPath $ddfPath -Value $lines -Encoding ASCII

    try {
        $null = & makecab.exe /F $ddfPath 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw ("makecab.exe failed (exit {0})." -f $LASTEXITCODE)
        }
    }
    finally {
        Remove-Item -LiteralPath $ddfPath -Force -ErrorAction SilentlyContinue
    }

    if (-not (Test-Path -LiteralPath $destFull)) {
        throw ("makecab.exe did not produce the expected archive: {0}" -f $destFull)
    }

    return $destFull
}
