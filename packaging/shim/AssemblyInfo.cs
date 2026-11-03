// Assembly-level metadata of the Domovoy portable launcher.
//
// Why a dedicated file: the Win32 VERSIONINFO resource of the compiled exe
// (Explorer "Details", SmartScreen, winget detection, AV heuristics) is
// generated from these attributes by both build paths:
//   - CI: csc.exe reads the attributes and emits VERSIONINFO automatically,
//     /win32icon merges the application icon into the same resource;
//   - sandbox: Roslyn receives a generated Win32 .res (icons + VERSIONINFO)
//     built from the same version by the sandbox build driver.
// The version here is pinned to the module manifest by a hard gate in
// tools/Build-PortableExe.ps1 (and re-checked at runtime by --selftest via
// AssemblyInformationalVersionAttribute), so the two cannot drift.
//
// NOTE: this file carries Cyrillic text and is saved as UTF-8 with a BOM -
// the in-box csc.exe reads BOM-less UTF-8 through the system ANSI codepage
// and would mangle the FileDescription on windows-latest runners.

using System.Reflection;
using System.Runtime.InteropServices;

[assembly: AssemblyTitle("Домовой (Domovoy) - Windows Tweaker")]
[assembly: AssemblyDescription("Ledger-based Windows tweaker: change ledger, per-feature undo, drift sentinel with opt-in auto-heal. Portable single-file launcher.")]
[assembly: AssemblyConfiguration("")]
[assembly: AssemblyCompany("Domovoy contributors")]
[assembly: AssemblyProduct("Domovoy")]
[assembly: AssemblyCopyright("(c) 2026 rtynbirf. MIT licensed.")]
[assembly: AssemblyTrademark("")]
[assembly: ComVisible(false)]
[assembly: AssemblyVersion("1.6.0.0")]
[assembly: AssemblyFileVersion("1.6.0.0")]
[assembly: AssemblyInformationalVersion("1.6.0")]
