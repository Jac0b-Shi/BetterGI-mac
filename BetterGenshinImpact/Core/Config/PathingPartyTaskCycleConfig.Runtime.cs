using BetterGenshinImpact.Helpers;
using System;

namespace BetterGenshinImpact.Core.Config;

/// <summary>
/// 使用已初始化服务器时间服务的周期计算入口。
/// </summary>
public partial class PathingPartyTaskCycleConfig
{
    public int GetExecutionOrder()
    {
        return GetExecutionOrder(IsBoundaryTimeBasedOnServerTime
            ? ServerTimeHelper.GetServerTimeNow()
            : DateTimeOffset.Now);
    }
}
