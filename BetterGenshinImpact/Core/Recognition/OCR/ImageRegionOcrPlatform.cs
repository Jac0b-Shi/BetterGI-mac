using System;
using System.Threading;

namespace BetterGenshinImpact.Core.Recognition.OCR;

/// <summary>Composition boundary used by the shared ImageRegion OCR paths.</summary>
public static class ImageRegionOcrPlatform
{
    private static IOcrService? _current;

    public static IOcrService Current => Volatile.Read(ref _current)
        ?? throw new InvalidOperationException("ImageRegion OCR service has not been composed.");

    public static void Configure(IOcrService service)
    {
        ArgumentNullException.ThrowIfNull(service);
        if (Interlocked.CompareExchange(ref _current, service, null) is not null)
            throw new InvalidOperationException("ImageRegion OCR service has already been configured.");
    }
}
