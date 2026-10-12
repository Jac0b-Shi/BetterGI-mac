using System;
using System.Threading;
namespace BetterGenshinImpact.Core.Mask;
/// <summary>截图根区域使用会话绘制入口；普通 Region 仍可使用显式空板。</summary>
public static class MaskWindowDrawingPlatform
{
    private static IMaskWindowDrawingBoard? _current;
    public static IMaskWindowDrawingBoard Current => Volatile.Read(ref _current)
#if BGI_PLATFORM_MAC
        ?? throw new InvalidOperationException("Mask drawing board has not been composed.");
#else
        ?? BetterGenshinImpact.GameTask.TaskContext.Instance().Runtime?.MaskWindowDrawingBoard
        ?? NullMaskWindowDrawingBoard.Instance;
#endif
    public static void Configure(IMaskWindowDrawingBoard board)
    {
        ArgumentNullException.ThrowIfNull(board);
        if (Interlocked.CompareExchange(ref _current, board, null) is not null)
            throw new InvalidOperationException("Mask drawing board has already been composed.");
    }
}
