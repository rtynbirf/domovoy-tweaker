// Domovoy portable shim (domovoy.exe).
//
// Why this file exists: the winget-cli manifest validator accepts only one
// file extension for NestedInstallerType "portable" targets -
// s_AllowedPortableFiletypes = { ".exe" } (ManifestValidation.cpp,
// ManifestError::InvalidPortableFiletype). The winget-pkgs validation
// pipeline rejected the previous target Domovoy/domovoy.ps1 for exactly
// this reason (PR microsoft/winget-pkgs#469700, verdict 2026-11-03).
//
// What it does: forwards the call to the PowerShell shim domovoy.ps1 that
// ships next to it inside the Domovoy/ package directory. No logic of its
// own - the same thin-client rule the GUI follows: every invocation maps
// to exactly one public Domovoy command, all semantics live in the module.
//
// How it is built: compiled by the CI/release pipeline with the .NET
// Framework csc.exe that ships on every Windows runner; the source is this
// file and the compiled executable is never committed to the repository.
//
// Production path note: winget installs portable executables by copying
// them into the WinGet Packages folder and creating a symlink in the
// WinGet Links folder (which is on PATH). When invoked through the symlink
// the process path points at the Links folder - so the shim resolves the
// final path of its own executable (GetFinalPathNameByHandle) and looks
// for domovoy.ps1 next to the REAL file, falling back to the base
// directory when resolution fails.
using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

static class DomovoyShim
{
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern IntPtr CreateFileW(
        string filename, uint desiredAccess, uint shareMode, IntPtr securityAttributes,
        uint creationDisposition, uint flagsAndAttributes, IntPtr templateFile);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern uint GetFinalPathNameByHandleW(IntPtr file, StringBuilder buffer, uint length, uint flags);

    [DllImport("kernel32.dll")]
    private static extern bool CloseHandle(IntPtr handle);

    private const uint GENERIC_READ = 0x80000000;
    private const uint FILE_SHARE_READ = 0x1;
    private const uint FILE_SHARE_WRITE = 0x2;
    private const uint FILE_SHARE_DELETE = 0x4;
    private const uint OPEN_EXISTING = 0x3;
    private const uint FILE_FLAG_BACKUP_SEMANTICS = 0x02000000;

    static int Main(string[] args)
    {
        string script = FindShimScript();
        if (script == null)
        {
            Console.Error.WriteLine("domovoy: cannot find domovoy.ps1 next to the executable.");
            return 2;
        }

        var start = new ProcessStartInfo();
        start.FileName = "powershell.exe";
        start.UseShellExecute = false;
        var line = new StringBuilder();
        line.Append("-NoLogo -NoProfile -ExecutionPolicy Bypass -File \"");
        line.Append(script);
        line.Append("\"");
        foreach (string a in args)
        {
            line.Append(' ');
            AppendQuoted(line, a);
        }
        start.Arguments = line.ToString();

        using (Process p = Process.Start(start))
        {
            p.WaitForExit();
            return p.ExitCode;
        }
    }

    // domovoy.ps1 sits next to the real (symlink-resolved) executable.
    static string FindShimScript()
    {
        string exe = GetFinalPathOfSelf();
        if (!string.IsNullOrEmpty(exe))
        {
            string candidate = Path.Combine(Path.GetDirectoryName(exe), "domovoy.ps1");
            if (File.Exists(candidate))
            {
                return candidate;
            }
        }
        string fallback = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "domovoy.ps1");
        if (File.Exists(fallback))
        {
            return fallback;
        }
        return null;
    }

    static string GetFinalPathOfSelf()
    {
        try
        {
            string processPath = Process.GetCurrentProcess().MainModule.FileName;
            IntPtr h = CreateFileW(processPath, GENERIC_READ,
                FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, IntPtr.Zero,
                OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, IntPtr.Zero);
            if (h == IntPtr.Zero || h == (IntPtr)(-1))
            {
                return null;
            }
            try
            {
                var sb = new StringBuilder(1024);
                uint len = GetFinalPathNameByHandleW(h, sb, (uint)sb.Capacity, 0);
                if (len == 0 || len >= (uint)sb.Capacity)
                {
                    return null;
                }
                string final = sb.ToString();
                // "\\?\C:\..." -> "C:\..."; "\\?\UNC\server\share" -> "\\server\share".
                if (final.StartsWith(@"\\?\", StringComparison.Ordinal))
                {
                    final = final.Substring(4);
                    if (final.StartsWith(@"UNC\", StringComparison.Ordinal))
                    {
                        final = @"\" + final.Substring(3);
                    }
                }
                return final;
            }
            finally
            {
                CloseHandle(h);
            }
        }
        catch
        {
            return null;
        }
    }

    // Windows command-line quoting per the standard argv rules: wrap in
    // quotes when the argument contains a space, a tab or a quote (or is
    // empty); double the backslashes that immediately precede a quote.
    static void AppendQuoted(StringBuilder sb, string a)
    {
        if (a.Length > 0 && a.IndexOfAny(new char[] { ' ', '\t', '"' }) < 0)
        {
            sb.Append(a);
            return;
        }
        sb.Append('"');
        int backslashes = 0;
        foreach (char c in a)
        {
            if (c == '\\')
            {
                backslashes++;
                continue;
            }
            if (c == '"')
            {
                sb.Append('\\', backslashes * 2 + 1);
                sb.Append('"');
            }
            else
            {
                sb.Append('\\', backslashes);
                sb.Append(c);
            }
            backslashes = 0;
        }
        sb.Append('\\', backslashes * 2);
        sb.Append('"');
    }
}
