using BetterGenshinImpact.GameTask.Shell;
using System;
using System.Diagnostics;
using System.Threading;
using System.Threading.Tasks;

namespace BetterGenshinImpact.GameTask;

public sealed class WindowsShellTaskPlatform : IShellTaskPlatform
{
    public void ActivateGameWindow() => SystemControl.ActivateWindow();

    public async Task<ShellExecutionRecord> ExecuteAsync(
        ShellTaskParam param, bool waitForExit, CancellationToken cancellationToken)
    {
        using var cmd = new Process();
        cmd.StartInfo = new ProcessStartInfo
        {
            FileName = "cmd.exe",
            Arguments = "/k @echo off",
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            CreateNoWindow = param.NoWindow,
            UseShellExecute = false
        };
        cmd.Start();
        await cmd.StandardInput.WriteLineAsync(param.Command.AsMemory(), cancellationToken);
        await cmd.StandardInput.FlushAsync(cancellationToken);
        cmd.StandardInput.Close();
        if (!waitForExit) return new ShellExecutionRecord(false, "", "");
        await cmd.WaitForExitAsync(cancellationToken);
        var outputShell = "";
        var outputText = "";
        if (param.Output)
        {
            outputShell = await cmd.StandardOutput.ReadLineAsync(cancellationToken) ?? "";
            outputText = await cmd.StandardOutput.ReadToEndAsync(cancellationToken);
        }
        if (cmd.HasExited) return new ShellExecutionRecord(true, outputShell, outputText);
        cmd.Kill();
        return new ShellExecutionRecord(false, outputShell, outputText);
    }
}
