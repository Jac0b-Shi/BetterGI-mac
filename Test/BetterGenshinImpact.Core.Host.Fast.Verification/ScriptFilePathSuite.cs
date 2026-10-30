using BetterGenshinImpact.Core.Host.Runtime;
using BetterGenshinImpact.Core.Script.Dependence;
using BetterGenshinImpact.Core.Script.Utils;
using BetterGenshinImpact.Verification.Framework;
using Microsoft.Extensions.Logging.Abstractions;

namespace BetterGenshinImpact.Core.Host.Fast.Verification;

public sealed class ScriptFilePathSuite : IVerificationSuite
{
    public string Name => "script-file-path";

    public async Task RunAsync(
        VerificationContext context,
        CancellationToken cancellationToken)
    {
        try
        {
            ScriptHostServices.Configure(
                new MacScriptHostServices(NullLoggerFactory.Instance));
        }
        catch (InvalidOperationException)
        {
            // Another suite already composed the process-wide script services.
        }

        var root = Path.Combine(
            Path.GetTempPath(), $"bettergi-script-file-{Guid.NewGuid():N}");
        Directory.CreateDirectory(root);
        var externalRoot = root + "-external";
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

            var files = new LimitedFile(root);
            context.Require(
                files.WriteTextSync(@"local\sync.txt", "sync") &&
                File.ReadAllText(Path.Combine(root, "local", "sync.txt")) == "sync",
                "LimitedFile rejected a valid relative path during synchronous writes.");
            context.Require(
                await files.WriteText("local/async.json", "{\"ok\":true}") &&
                File.Exists(Path.Combine(root, "local", "async.json")),
                "LimitedFile rejected a valid relative path during asynchronous writes.");
            Directory.CreateDirectory(externalRoot);
            var protectedFile = Path.Combine(externalRoot, "keep.txt");
            await File.WriteAllTextAsync(protectedFile, "keep", cancellationToken);
            Directory.CreateSymbolicLink(Path.Combine(root, "linked"), externalRoot);
            context.Require(!files.DeletePathSync("linked/keep.txt") && File.Exists(protectedFile) &&
                            files.DeletePathSync("linked") && File.Exists(protectedFile),
                "DeletePathSync followed an external parent link or failed to remove only the link itself.");
            var relativeRoot = new LimitedFile(Path.GetRelativePath(Environment.CurrentDirectory, root));
            context.Require(!files.DeletePathSync(".") && !relativeRoot.DeletePathSync(".") && Directory.Exists(root),
                "DeletePathSync accepted deletion of the script root with an absolute or relative root.");
            context.Require(files.DeletePathSync("local") && !Directory.Exists(Path.Combine(root, "local")) &&
                            !files.DeletePathSync($"../{Path.GetFileName(sibling)}"),
                "DeletePathSync failed a contained deletion or accepted an escaped path.");
        }
        finally
        {
            Directory.Delete(root, recursive: true);
            if (Directory.Exists(externalRoot)) Directory.Delete(externalRoot, recursive: true);
        }

        cancellationToken.ThrowIfCancellationRequested();
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
