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
# Deliberately a PLAIN script with no [Parameter()]/[CmdletBinding()]
# attributes at all: `powershell.exe -File` (and `pwsh -File` alike) appends
# a phantom empty argument to a script that carries parameter attributes -
# the probe proves it (argsCount=1 with [Parameter()], argsCount=0 without),
# and that phantom is what failed the CI smoke with "A positional parameter
# cannot be found that accepts argument '$null'" (runs 65-66). A plain
# param + the automatic $args + a manual guard keeps the forwarding honest
# on every engine, and simple-function token passing sends '-Flag value'
# pairs through verbatim.
param([string]$Command)

# Everything after the command name is forwarded verbatim via the
# automatic $args collection.
$Arguments = @($args)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Command)) {
    throw "Usage: domovoy <DomovoyCommand> [args...] - the shim forwards public Domovoy commands only (see: Get-Command -Module Domovoy)"
}

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

if ($Command -eq 'Show-Domovoy') {
    # v1.6.0: the portable launcher starts the GUI detached with no console
    # window - a fatal error here (module import failure, missing WinForms)
    # must not vanish into a hidden console. Surface it: log file + dialog.
    try {
        & $Command @Arguments
    }
    catch {
        $fatal = $_
        $logDir = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) 'Domovoy\logs'
        try { $null = New-Item -Path $logDir -ItemType Directory -Force } catch { }
        $logFile = Join-Path $logDir ("domovoy-fatal-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
        try {
            $detail = @(
                $fatal.ToString(),
                '',
                ($fatal.InvocationInfo | Out-String),
                $fatal.ScriptStackTrace
            ) -join "`r`n"
            Set-Content -LiteralPath $logFile -Value $detail -Encoding UTF8
        }
        catch { $logFile = '(log write failed)' }
        $message = @(
            'ДОМОВОЙ: фатальная ошибка запуска GUI / fatal GUI startup error',
            '',
            $fatal.Exception.Message,
            '',
            ('Журнал / log: ' + $logFile),
            'Issues: https://github.com/rtynbirf/domovoy-tweaker/issues'
        ) -join "`r`n"
        try {
            Add-Type -AssemblyName System.Windows.Forms
            [void][System.Windows.Forms.MessageBox]::Show($message, 'Domovoy', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
        catch {
            Write-Error -ErrorRecord $fatal
        }
        exit 1
    }
}
else {
    & $Command @Arguments
}
