namespace BetterGenshinImpact.Verification.Framework;

public static class VerificationRunner
{
    public static async Task<int> RunAsync(
        string[] args,
        IReadOnlyList<IVerificationSuite> suites,
        CancellationToken cancellationToken = default)
    {
        var selectedNames = ParseSuiteNames(args);
        var selected = selectedNames.Count == 0 || selectedNames.Contains("all")
            ? suites
            : suites.Where(suite => selectedNames.Contains(suite.Name)).ToArray();
        if (selected.Count == 0)
            throw new ArgumentException($"No verification suite matched: {string.Join(", ", selectedNames)}");

        var context = new VerificationContext(Console.Out);
        foreach (var suite in selected)
        {
            context.Output.WriteLine($"[suite:{suite.Name}] start");
            await suite.RunAsync(context, cancellationToken);
            context.Output.WriteLine($"[suite:{suite.Name}] passed");
        }
        return 0;
    }

    private static HashSet<string> ParseSuiteNames(string[] args)
    {
        var names = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        for (var index = 0; index < args.Length; index++)
        {
            if (args[index] != "--suite") continue;
            if (++index >= args.Length) throw new ArgumentException("--suite requires a value.");
            foreach (var name in args[index].Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
                names.Add(name);
        }
        return names;
    }
}
