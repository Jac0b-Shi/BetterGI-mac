using System;
using System.Collections.Generic;
using System.Threading;
using BetterGenshinImpact.Core.Recognition.OCR;

namespace BetterGenshinImpact.GameTask.Common.Job;

public sealed record CraftingBenchConfig(string Name, int MinResinToKeep);

public interface IGoToCraftingBenchRuntimePlatform
{
    string SelectedConfigName { get; }
    IOcrService OcrService { get; }
    IReadOnlyList<CraftingBenchConfig> LoadConfigs();
}

public static class GoToCraftingBenchRuntimePlatform
{
    private static IGoToCraftingBenchRuntimePlatform? _current;
    public static IGoToCraftingBenchRuntimePlatform Current => Volatile.Read(ref _current)
        ?? throw new InvalidOperationException("GoToCraftingBench runtime platform has not been composed.");

    public static void Configure(IGoToCraftingBenchRuntimePlatform platform)
    {
        ArgumentNullException.ThrowIfNull(platform);
        if (Interlocked.CompareExchange(ref _current, platform, null) is not null)
            throw new InvalidOperationException("GoToCraftingBench runtime platform has already been configured.");
    }
}
