# Domovoy module loader.
# Private helpers are dot-sourced first, then public commands.

$privateDir = Join-Path -Path $PSScriptRoot -ChildPath 'Private'
$publicDir = Join-Path -Path $PSScriptRoot -ChildPath 'Public'

Get-ChildItem -LiteralPath $privateDir -Filter '*.ps1' -ErrorAction SilentlyContinue |
    ForEach-Object { . $_.FullName }

Get-ChildItem -LiteralPath $publicDir -Filter '*.ps1' -ErrorAction SilentlyContinue |
    ForEach-Object { . $_.FullName }

$publicNames = @(
    Get-ChildItem -LiteralPath $publicDir -Filter '*.ps1' -ErrorAction SilentlyContinue |
        ForEach-Object { $_.BaseName }
)

Export-ModuleMember -Function $publicNames
