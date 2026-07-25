using BetterGenshinImpact.Core.Script.Utils;
using BetterGenshinImpact.Verification.Framework;

namespace BetterGenshinImpact.Core.Host.Fast.Verification;

public sealed class ScriptFilePathSuite : IVerificationSuite
{
    public string Name => "script-file-path";

    public Task RunAsync(
        VerificationContext context,
        CancellationToken cancellationToken)
    {
        var root = Path.Combine(
            Path.GetTempPath(), $"bettergi-script-file-{Guid.NewGuid():N}");
        Directory.CreateDirectory(root);
        try
        {
            var expected = Path.Combine(root, "data", "store.json");
            context.Require(
                ScriptUtils.NormalizePath(root, @"data\store.json") == expected &&
                ScriptUtils.NormalizePath(root, "data/store.json") == expected,
                "Script file paths did not preserve relative Windows and POSIX separators.");

            context.Require(
                ScriptUtils.GetScriptRelativePath(root, expected) == @"data\store.json",
                "Script directory listings did not preserve the upstream Windows path representation.");

            context.Require(
                Throws<ArgumentException>(() =>
                    ScriptUtils.NormalizePath(root, @"C:\Users\script\data\store.json")) &&
                Throws<ArgumentException>(() =>
                    ScriptUtils.NormalizePath(root, @"\\server\share\store.json")),
                "Script file paths accepted a Windows absolute path on macOS.");

            var sibling = root + "-outside";
            context.Require(
                Throws<ArgumentException>(() =>
                    ScriptUtils.NormalizePath(root, $"../{Path.GetFileName(sibling)}/store.json")),
                "Script file path validation accepted a sibling directory with the same prefix.");
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }

        cancellationToken.ThrowIfCancellationRequested();
        return Task.CompletedTask;
    }

    private static bool Throws<TException>(Action action)
        where TException : Exception
    {
        try
        {
            action();
            return false;
        }
        catch (TException)
        {
            return true;
        }
    }
}
