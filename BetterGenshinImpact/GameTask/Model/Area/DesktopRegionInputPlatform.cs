using System;
using System.Threading;
using BetterGenshinImpact.Platform.Abstractions;

namespace BetterGenshinImpact.GameTask.Model.Area;

/// <summary>
/// Composition boundary for the input side effects performed by the shared Region graph.
/// The business coordinate conversion remains in <see cref="DesktopRegion"/>; hosts only
/// provide the native semantic input backend.
/// </summary>
public static class DesktopRegionInputPlatform
{
    private static IInputBackend? _current;

    public static IInputBackend Current => Volatile.Read(ref _current)
        ?? throw new InvalidOperationException("DesktopRegion input backend has not been composed.");

    public static void Configure(IInputBackend backend)
    {
        ArgumentNullException.ThrowIfNull(backend);
        if (Interlocked.CompareExchange(ref _current, backend, null) is not null)
            throw new InvalidOperationException("DesktopRegion input backend has already been configured.");
    }
}
