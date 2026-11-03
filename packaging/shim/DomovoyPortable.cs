// Domovoy portable single-file launcher (Domovoy-<version>-Portable.exe).
//
// What it is: the whole release payload (the Domovoy module, the feature
// catalog, the schemas, both CLI shims, README, LICENSE) embedded into one
// executable. One download, one double-click: the launcher unpacks the
// payload next to itself (or under %LOCALAPPDATA%\Domovoy\app when the
// executable's folder is read-only), then opens the Domovoy GUI
// (Show-Domovoy) through pwsh.exe / powershell.exe. Any command-line
// arguments are forwarded verbatim to the CLI shim domovoy.ps1, so the same
// file doubles as the CLI entry point:
//   Domovoy-Portable.exe Get-DomovoyFeature
//
// Thin-client rule, same as the winget shim (DomovoyShim.cs): the launcher
// adds NO tweaker logic of its own - extraction and process start only.
// Every semantic lives in the module and the domovoy.ps1 shim inside the
// payload.
//
// Safety properties:
//   - extraction is confined to the target root (path traversal guard:
//     no absolute paths, no drive letters, no "..", prefix-checked targets);
//   - a marker file stores the payload SHA-256: an already-extracted
//     payload is never unpacked twice, and a half-finished extraction
//     (no marker) is redone on the next run;
//   - --selftest: extraction into a temp directory, required-file checks,
//     catalog/schema non-emptiness and a module-manifest-version ==
//     payload-version comparison. Cross-platform on purpose - this is how
//     the build gate machine-checks the packaging without Windows;
//   - --extract [dir]: unpack without starting anything (transparency).
//
// How it is built: compiled with the .NET Framework csc.exe that ships on
// every Windows runner (C# 5 source, .NET Framework 4.5+ API surface only)
// by tools/Build-PortableExe.ps1; the payload zip and the payload version
// file travel as managed resources named "Domovoy.Portable.payload.zip"
// and "Domovoy.Portable.payload.version". The compiled executable is never
// committed to the repository - it is a release asset only.
using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;

internal static class DomovoyPortable
{
    private const string PayloadResource = "Domovoy.Portable.payload.zip";
    private const string VersionResource = "Domovoy.Portable.payload.version";
    private const string MarkerName = ".domovoy-payload-ok";
    private const string ModuleDirName = "Domovoy";
    private const string ShimFileName = "domovoy.ps1";
    private const string GuiCommand = "Show-Domovoy";
    private const string RepoUrl = "https://github.com/rtynbirf/domovoy-tweaker";

    private static int Main(string[] args)
    {
        try { Console.OutputEncoding = Encoding.UTF8; }
        catch { /* redirected console or already set - the banner is ASCII */ }

        string version = ReadEmbeddedText(VersionResource).Trim();
        if (version.Length == 0)
        {
            return Fail("payload version resource is missing or empty", args);
        }

        string payloadSha = Sha256OfResource(PayloadResource);

        if (Contains(args, "--selftest"))
        {
            return SelfTest(version, payloadSha);
        }

        Banner(version, payloadSha);

        string exeDir = SafeExeDirectory();
        if (exeDir == null)
        {
            return Fail("cannot resolve the executable location", args);
        }

        string extractTarget = null;
        bool extractOnly = false;
        for (int i = 0; i < args.Length; i++)
        {
            if (string.Equals(args[i], "--extract", StringComparison.OrdinalIgnoreCase))
            {
                extractOnly = true;
                if (i + 1 < args.Length)
                {
                    extractTarget = args[i + 1];
                }
            }
        }

        string root = ResolveExtractionRoot(exeDir, version, extractTarget);
        string marker = Path.Combine(root, MarkerName);
        if (File.Exists(marker) && ReadTextOrNull(marker) == payloadSha)
        {
            Console.WriteLine("Payload ready: " + root);
        }
        else
        {
            Console.WriteLine("Extracting payload to: " + root);
            try
            {
                ExtractPayload(root);
                File.WriteAllText(marker, payloadSha, new UTF8Encoding(false));
            }
            catch (Exception ex)
            {
                return Fail("payload extraction failed: " + ex.Message, args);
            }
            Console.WriteLine("Payload extracted.");
        }

        if (extractOnly)
        {
            Console.WriteLine("Extracted without launching (per --extract): " + root);
            return 0;
        }

        string shim = Path.Combine(Path.Combine(root, ModuleDirName), ShimFileName);
        if (!File.Exists(shim))
        {
            return Fail("domovoy.ps1 not found in the extracted payload: " + shim, args);
        }

        string engine = FindEngine();
        if (engine == null)
        {
            return Fail("neither pwsh.exe nor powershell.exe was found (set DOMOVOY_PSEXE to override)", args);
        }

        bool guiMode = args.Length == 0;
        ProcessStartInfo start = new ProcessStartInfo();
        start.FileName = engine;
        start.Arguments = BuildEngineArguments(shim, args, guiMode);
        start.WorkingDirectory = root;
        start.UseShellExecute = false;
        if (guiMode)
        {
            // The GUI opens as its own top-level window; the host console is
            // minimized, not hidden, so an engine error stays reachable in
            // the taskbar instead of vanishing with the child process.
            start.WindowStyle = ProcessWindowStyle.Minimized;
        }

        Console.WriteLine();
        Console.WriteLine("Engine:  " + engine);
        Console.WriteLine();

        int code;
        using (Process p = Process.Start(start))
        {
            p.WaitForExit();
            code = p.ExitCode;
        }

        if (guiMode && code != 0)
        {
            Console.Error.WriteLine("Exit code " + code + " - restore this window to see the error output.");
            Console.Error.Write("Press Enter to close... ");
            Console.ReadLine();
        }
        return code;
    }

    private static void Banner(string version, string payloadSha)
    {
        Console.WriteLine("============================================================");
        Console.WriteLine(" Domovoy " + version + " - portable single-file launcher");
        Console.WriteLine(" " + RepoUrl);
        Console.WriteLine("============================================================");
        Console.WriteLine("Payload:  " + PayloadResource);
        Console.WriteLine("SHA-256:  " + payloadSha);
    }

    // Build gate: extract into a temp directory and machine-check the
    // packaging contract. Deliberately free of Windows-only APIs so the
    // same check runs on any OS (the sandbox build runs it under pwsh).
    private static int SelfTest(string version, string payloadSha)
    {
        string temp = Path.Combine(
            Path.GetTempPath(),
            "domovoy-selftest-" + Guid.NewGuid().ToString("N").Substring(0, 8));
        try
        {
            Console.WriteLine("SelfTest: extracting payload to " + temp);
            int entries = ExtractPayload(temp);

            string[] required = new string[]
            {
                "README.md",
                "LICENSE",
                "Domovoy/Domovoy.psd1",
                "Domovoy/Domovoy.psm1",
                "Domovoy/domovoy.ps1",
                "Domovoy/domovoy.exe"
            };
            foreach (string rel in required)
            {
                string path = Path.Combine(temp, rel.Replace('/', Path.DirectorySeparatorChar));
                if (!File.Exists(path))
                {
                    Console.Error.WriteLine("SelfTest FAIL: missing " + rel);
                    return 1;
                }
            }

            if (Directory.GetFiles(Path.Combine(temp, "Domovoy", "config"), "*", SearchOption.AllDirectories).Length == 0)
            {
                Console.Error.WriteLine("SelfTest FAIL: the feature catalog (config/) is empty");
                return 1;
            }
            if (Directory.GetFiles(Path.Combine(temp, "Domovoy", "schema"), "*", SearchOption.AllDirectories).Length == 0)
            {
                Console.Error.WriteLine("SelfTest FAIL: the schemas (schema/) are empty");
                return 1;
            }

            string psd1 = File.ReadAllText(Path.Combine(temp, "Domovoy", "Domovoy.psd1"));
            Match m = Regex.Match(psd1, "ModuleVersion\\s*=\\s*'([^']+)'");
            if (!m.Success || m.Groups[1].Value != version)
            {
                string found = m.Success ? m.Groups[1].Value : "(not found)";
                Console.Error.WriteLine("SelfTest FAIL: module manifest version " + found + " != payload version " + version);
                return 1;
            }

            Console.WriteLine(
                "SelfTest PASS: " + entries + " file entries, module version " + version +
                ", payload sha256 " + payloadSha);
            return 0;
        }
        finally
        {
            try { Directory.Delete(temp, true); }
            catch { /* best-effort cleanup */ }
        }
    }

    private static int ExtractPayload(string root)
    {
        Directory.CreateDirectory(root);
        string rootFull = Path.GetFullPath(root);
        if (!rootFull.EndsWith(Path.DirectorySeparatorChar.ToString(), StringComparison.Ordinal))
        {
            rootFull += Path.DirectorySeparatorChar;
        }

        byte[] payload = ReadEmbeddedResource(PayloadResource);
        int count = 0;
        using (MemoryStream archiveStream = new MemoryStream(payload))
        using (ZipArchive archive = new ZipArchive(archiveStream, ZipArchiveMode.Read))
        {
            foreach (ZipArchiveEntry entry in archive.Entries)
            {
                // Normalize first: archivers disagree on the separator
                // (Compress-Archive historically writes backslashes).
                string name = entry.FullName.Replace('\\', '/');
                if (name.Length == 0)
                {
                    continue;
                }
                if (name.IndexOf("..", StringComparison.Ordinal) >= 0
                    || name.StartsWith("/", StringComparison.Ordinal)
                    || name.IndexOf(':') >= 0)
                {
                    throw new IOException("unsafe payload entry: " + entry.FullName);
                }

                string target = Path.GetFullPath(
                    Path.Combine(rootFull, name.Replace('/', Path.DirectorySeparatorChar)));
                // rootFull carries the trailing separator, so this prefix
                // check cannot be fooled by a sibling directory name.
                if (!target.StartsWith(rootFull, StringComparison.OrdinalIgnoreCase))
                {
                    throw new IOException("payload entry escapes the target root: " + entry.FullName);
                }

                if (name.EndsWith("/", StringComparison.Ordinal))
                {
                    Directory.CreateDirectory(target);
                    continue;
                }

                string dir = Path.GetDirectoryName(target);
                if (!string.IsNullOrEmpty(dir))
                {
                    Directory.CreateDirectory(dir);
                }
                using (Stream source = entry.Open())
                using (FileStream destination = File.Create(target))
                {
                    source.CopyTo(destination);
                }
                count++;
            }
        }
        return count;
    }

    private static string ResolveExtractionRoot(string exeDir, string version, string extractTarget)
    {
        if (!string.IsNullOrEmpty(extractTarget))
        {
            return Path.GetFullPath(extractTarget);
        }
        string preferred = Path.Combine(exeDir, "Domovoy-" + version);
        if (IsWritable(preferred))
        {
            return preferred;
        }
        string fallback = Path.Combine(
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Domovoy"),
            Path.Combine("app", version));
        Console.WriteLine("Executable folder is not writable - falling back to: " + fallback);
        return fallback;
    }

    private static bool IsWritable(string dir)
    {
        try
        {
            Directory.CreateDirectory(dir);
            string probe = Path.Combine(dir, ".domovoy-write-probe");
            File.WriteAllText(probe, "probe");
            File.Delete(probe);
            return true;
        }
        catch
        {
            return false;
        }
    }

    private static string FindEngine()
    {
        string overrideEngine = Environment.GetEnvironmentVariable("DOMOVOY_PSEXE");
        if (!string.IsNullOrEmpty(overrideEngine) && File.Exists(overrideEngine))
        {
            return overrideEngine;
        }
        string programFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
        string pwshStable = Path.Combine(Path.Combine(programFiles, "PowerShell"), "7\\pwsh.exe");
        if (File.Exists(pwshStable))
        {
            return pwshStable;
        }
        string pwshOnPath = FindOnPath("pwsh.exe");
        if (pwshOnPath != null)
        {
            return pwshOnPath;
        }
        string windowsDir = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
        string ps51 = Path.Combine(windowsDir, "System32\\WindowsPowerShell\\v1.0\\powershell.exe");
        if (File.Exists(ps51))
        {
            return ps51;
        }
        return FindOnPath("powershell.exe");
    }

    private static string FindOnPath(string fileName)
    {
        string path = Environment.GetEnvironmentVariable("PATH");
        if (string.IsNullOrEmpty(path))
        {
            return null;
        }
        foreach (string raw in path.Split(new char[] { Path.PathSeparator }))
        {
            if (raw.Trim().Length == 0)
            {
                continue;
            }
            string candidate = Path.Combine(raw.Trim(), fileName);
            if (File.Exists(candidate))
            {
                return candidate;
            }
        }
        return null;
    }

    private static string BuildEngineArguments(string shim, string[] args, bool guiMode)
    {
        StringBuilder line = new StringBuilder();
        line.Append("-NoLogo -NoProfile -ExecutionPolicy Bypass");
        if (guiMode)
        {
            line.Append(" -WindowStyle Minimized");
        }
        line.Append(" -File \"");
        line.Append(shim);
        line.Append("\"");
        if (args.Length == 0)
        {
            line.Append(' ');
            line.Append(GuiCommand);
        }
        else
        {
            foreach (string a in args)
            {
                line.Append(' ');
                AppendQuoted(line, a);
            }
        }
        return line.ToString();
    }

    // Windows command-line quoting per the standard argv rules - the same
    // routine DomovoyShim.cs ships, kept byte-for-byte in behaviour.
    private static void AppendQuoted(StringBuilder sb, string a)
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

    private static byte[] ReadEmbeddedResource(string name)
    {
        Assembly assembly = Assembly.GetExecutingAssembly();
        using (Stream stream = assembly.GetManifestResourceStream(name))
        {
            if (stream == null)
            {
                throw new IOException("embedded resource not found: " + name);
            }
            using (MemoryStream buffer = new MemoryStream())
            {
                stream.CopyTo(buffer);
                return buffer.ToArray();
            }
        }
    }

    private static string ReadEmbeddedText(string name)
    {
        return Encoding.UTF8.GetString(ReadEmbeddedResource(name));
    }

    private static string Sha256OfResource(string name)
    {
        using (SHA256 sha = SHA256.Create())
        {
            byte[] hash = sha.ComputeHash(ReadEmbeddedResource(name));
            StringBuilder sb = new StringBuilder(hash.Length * 2);
            foreach (byte b in hash)
            {
                sb.Append(b.ToString("x2"));
            }
            return sb.ToString();
        }
    }

    private static string ReadTextOrNull(string path)
    {
        try
        {
            return File.ReadAllText(path).Trim();
        }
        catch
        {
            return null;
        }
    }

    private static string SafeExeDirectory()
    {
        try
        {
            return Path.GetDirectoryName(Path.GetFullPath(Assembly.GetExecutingAssembly().Location));
        }
        catch
        {
            return null;
        }
    }

    private static bool Contains(string[] args, string flag)
    {
        foreach (string a in args)
        {
            if (string.Equals(a, flag, StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }
        return false;
    }

    private static int Fail(string message, string[] args)
    {
        Console.Error.WriteLine();
        Console.Error.WriteLine("domovoy-portable: " + message);
        if (args != null && args.Length == 0)
        {
            Console.Error.Write("Press Enter to close... ");
            Console.ReadLine();
        }
        return 1;
    }
}
