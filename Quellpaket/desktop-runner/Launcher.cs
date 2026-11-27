// Windows GUI-subsystem launcher. No console, Docker, Hyper-V or .NET SDK needed.
using System;
using System.Collections;
using System.Diagnostics;
using System.IO;
using System.Runtime.Serialization;
using System.Runtime.Serialization.Json;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Forms;

[DataContract]
public class EditorRequest {
    [DataMember] public string file;
    [DataMember] public string[] arguments;
    [DataMember] public string workingDirectory;
    [DataMember] public string runId;
}

internal static class Launcher {
    private static readonly object Gate = new object();
    private static string Root, RunId, Component;
    public static string Quote(string value) {
        StringBuilder result = new StringBuilder("\""); int slashes = 0;
        foreach(char c in value) {
            if(c == '\\') { slashes++; continue; }
            if(c == '"') { result.Append('\\', slashes * 2 + 1); result.Append(c); slashes = 0; continue; }
            result.Append('\\', slashes); slashes = 0; result.Append(c);
        }
        result.Append('\\', slashes * 2); return result.Append('"').ToString();
    }
    private static string Arguments(string[] values) {
        StringBuilder result = new StringBuilder();
        foreach(string value in values) { if(result.Length > 0) result.Append(' '); result.Append(Quote(value)); }
        return result.ToString();
    }
    private static string Safe(string text) {
        foreach(DictionaryEntry entry in Environment.GetEnvironmentVariables()) {
            string value = Convert.ToString(entry.Value);
            if(Regex.IsMatch(Convert.ToString(entry.Key), "token|api.?key|password|secret", RegexOptions.IgnoreCase) && value.Length > 3) text = text.Replace(value, "[REDACTED]");
        }
        text = Regex.Replace(text, @"(Bearer\s+|Basic\s+)[A-Za-z0-9+/_=.:-]+", "$1[REDACTED]", RegexOptions.IgnoreCase);
        return Regex.Replace(text, @"((?:api[_-]?key|password|access_token|refresh_token)\s*[""']?\s*[:=]\s*[""']?)[^\s""',;}]+", "$1[REDACTED]", RegexOptions.IgnoreCase);
    }
    private static string Json(string value) {
        StringBuilder result = new StringBuilder("\"");
        foreach(char c in value) { if(c == '\\' || c == '"') result.Append('\\').Append(c); else if(c < 32) result.Append("\\u").Append(((int)c).ToString("x4")); else result.Append(c); }
        return result.Append('"').ToString();
    }
    private static void Log(string level, string text) {
        if(String.IsNullOrEmpty(text)) return;
        text = Safe(text);
        lock(Gate) {
            string dir = Path.Combine(Root, "runtime", "launcher-logs"); Directory.CreateDirectory(dir);
            string utc = DateTime.UtcNow.ToString("o");
            File.AppendAllText(Path.Combine(dir, RunId + "-" + Component + ".log"), utc + " [" + level + "] " + text + Environment.NewLine, new UTF8Encoding(false));
            // The managed VS Code Output tails these logs; PS worker events use its own JSONL writer.
        }
    }
    private static void EditorStatus(string phase, string error) {
        if(Component != "editor") return;
        string file = Path.Combine(Root, "runtime", "launch-requests", RunId + ".status.json");
        File.WriteAllText(file, "{\"phase\":" + Json(phase) + ",\"error\":" + Json(Safe(error ?? "")) + "}", new UTF8Encoding(false));
    }
    private static int Capture(string file, string[] args, string cwd, int timeout) {
        ProcessStartInfo info = new ProcessStartInfo(file, Arguments(args));
        info.UseShellExecute = false; info.CreateNoWindow = true; info.WindowStyle = Component == "editor" ? ProcessWindowStyle.Normal : ProcessWindowStyle.Hidden;
        info.RedirectStandardInput = true; info.RedirectStandardOutput = true; info.RedirectStandardError = true;
        info.StandardOutputEncoding = Encoding.UTF8; info.StandardErrorEncoding = Encoding.UTF8; info.WorkingDirectory = cwd;
        using(Process process = new Process()) {
            using(ManualResetEvent outDone = new ManualResetEvent(false))
            using(ManualResetEvent errDone = new ManualResetEvent(false)) {
            process.StartInfo = info;
            process.OutputDataReceived += delegate(object sender, DataReceivedEventArgs e) { try { if(e.Data == null) outDone.Set(); else Log("INFO", e.Data); } catch {} };
            process.ErrorDataReceived += delegate(object sender, DataReceivedEventArgs e) { try { if(e.Data == null) errDone.Set(); else Log(Regex.IsMatch(e.Data, "warning|deprecat", RegexOptions.IgnoreCase) ? "WARN" : "ERROR", e.Data); } catch {} };
            Log("INFO", "Starting " + Path.GetFileName(file));
            if(!process.Start()) throw new InvalidOperationException("Process could not start.");
            EditorStatus("started", null);
            process.StandardInput.Close(); process.BeginOutputReadLine(); process.BeginErrorReadLine();
            if(!process.WaitForExit(timeout)) { process.Kill(); throw new TimeoutException("The launched worker exceeded its startup deadline."); }
            // A descendant may inherit a pipe. Never keep the desktop worker waiting on EOF.
            bool drainedOut = outDone.WaitOne(1000), drainedErr = errDone.WaitOne(1000);
            if(!drainedOut || !drainedErr) Log("WARN", "Output handles remain open after process exit; output draining was stopped at its deadline.");
            try { process.CancelOutputRead(); process.CancelErrorRead(); } catch(InvalidOperationException) {}
            int code = process.ExitCode; Log(code == 0 ? "INFO" : "ERROR", "Process exited with code " + code); return code;
            }
        }
    }
    [STAThread]
    private static int Main(string[] args) {
        Root = Path.GetFullPath(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "..", ".."));
        RunId = Guid.NewGuid().ToString("N"); Component = "desktop";
        bool editor = args.Length == 2 && args[0] == "--editor";
        try {
            if(editor) {
                Component = "editor";
                string requestPath = Path.GetFullPath(args[1]);
                string allowed = Path.Combine(Root, "runtime", "launch-requests") + Path.DirectorySeparatorChar;
                if(!requestPath.StartsWith(allowed, StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("Editor request is outside the managed directory.");
                EditorRequest request;
                using(FileStream input = File.OpenRead(requestPath)) request = (EditorRequest)new DataContractJsonSerializer(typeof(EditorRequest)).ReadObject(input);
                if(!Regex.IsMatch(request.runId ?? "", "^[a-f0-9]{32}$")) throw new InvalidOperationException("Invalid editor launch ID.");
                RunId = request.runId;
                return Capture(request.file, request.arguments, request.workingDirectory, Int32.MaxValue);
            }
            if(args.Length != 0) throw new InvalidOperationException("The desktop launcher does not accept shell commands.");
            string pwsh = File.ReadAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "powershell-path.txt"), Encoding.UTF8).Trim();
            Environment.SetEnvironmentVariable("LOKIENTE_LAUNCH_ID", RunId);
            int code = Capture(pwsh, new string[] { "-STA", "-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", Path.Combine(Root, "app", "Start-LocalAI.ps1"), "-InstallRoot", Root, "-Desktop" }, Root, 3600000);
            if(code != 0 && !File.Exists(Path.Combine(Root, "runtime", "launch-requests", RunId + ".diagnostic-started"))) throw new InvalidOperationException("Startup failed. See VS Code Output → LoKiEnte or runtime\\launcher-logs.");
            return code;
        } catch(Exception error) {
            try { Log("ERROR", error.ToString()); } catch {}
            try { EditorStatus("failed", error.Message); } catch {}
            if(!editor) MessageBox.Show(Safe(error.Message) + Environment.NewLine + "Details: " + Path.Combine(Root, "runtime", "launcher-logs"), "LoKiEnte startup", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}
