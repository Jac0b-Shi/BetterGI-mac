using Microsoft.Extensions.Localization;
using System;
using System.Threading;

namespace BetterGenshinImpact.GameTask.Model;

public interface ITaskParameterPlatform
{
    string GameCultureInfoName { get; }
    IStringLocalizer<T> GetStringLocalizer<T>();
}

public static class TaskParameterPlatform
{
    private static ITaskParameterPlatform? _current;
    public static ITaskParameterPlatform Current => Volatile.Read(ref _current)
        ?? throw new InvalidOperationException("Task parameter platform has not been composed.");
    public static void Configure(ITaskParameterPlatform platform)
    {
        ArgumentNullException.ThrowIfNull(platform);
        if (Interlocked.CompareExchange(ref _current, platform, null) is not null)
            throw new InvalidOperationException("Task parameter platform has already been configured.");
    }
}
