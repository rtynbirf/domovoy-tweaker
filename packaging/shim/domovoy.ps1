<#
.SYNOPSIS
    Domovoy CLI shim - the thin executable entry point for winget portable
    installs (NestedInstallerType: portable targets this file).

.DESCRIPTION
    The winget portable installer symlinks this script into the WinGet Links
    folder under the alias "domovoy". The shim imports the module that sits
    next to it (Domovoy/Domovoy.psd1 inside the unpacked package) and
    forwards the call to a public Domovoy command. It adds no logic of its
    own - the same thin-client rule the GUI follows: every invocation maps
    to exactly one public command, all semantics live in the module.

.EXAMPLE
    domovoy Get-DomovoyFeature

.EXAMPLE
    domovoy Invoke-DomovoyFeature privacy-telemetry

.EXAMPLE
    domovoy Show-Domovoy
#>
[CmdletBinding()]
param(
    # The public Domovoy command to invoke, e.g. Get-DomovoyFeature.
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$Command,

    # Everything after the command name is forwarded verbatim.
    [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
    [object[]]$Arguments
)

$ErrorActionPreference = 'Stop'

$moduleManifest = Join-Path -Path $PSScriptRoot -ChildPath 'Domovoy.psd1'
if (-not (Test-Path -LiteralPath $moduleManifest -PathType Leaf)) {
    throw "Domovoy module manifest not found next to the shim: $moduleManifest"
}

if (-not (Get-Module -Name Domovoy)) {
    Import-Module -Name $moduleManifest -Global
}

if ($Command -notmatch '^(\w+-)?Domovoy(\w+)?$') {
    throw "Unknown command '$Command' - the shim forwards public Domovoy commands only (see: Get-Command -Module Domovoy)"
}

& $Command @Arguments
