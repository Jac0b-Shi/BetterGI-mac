using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.GameTask.LogParse;
using Microsoft.Extensions.Logging;
using System;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;

namespace BetterGenshinImpact.GameTask.FarmingPlan;

public static class FarmingStatsMiyousheUpdater
{
    public static async Task UpdateAsync(
        OtherConfig otherConfig,
        ILogger logger,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        DailyFarmingData? dailyFarmingData = null;
        if (otherConfig.FarmingPlanConfig.MiyousheDataConfig.Enabled &&
            !string.IsNullOrEmpty(otherConfig.MiyousheConfig.Cookie))
        {
            try
            {
                var gameInfo = await TravelsDiaryDetailManager.UpdateTravelsDiaryDetailManager(
                    otherConfig.MiyousheConfig.Cookie, true);
                cancellationToken.ThrowIfCancellationRequested();
                var actionItems = TravelsDiaryDetailManager.loadNowDayActionItems(gameInfo);
                var statistics = new MoraStatistics();
                statistics.ActionItems.AddRange(actionItems);
                dailyFarmingData = FarmingStatsRecorder.ReadDailyFarmingData();
                if (actionItems.Count > 0)
                {
                    dailyFarmingData.MiyousheTotalEliteMobCount =
                        statistics.EliteGameStatistics;
                    dailyFarmingData.MiyousheTotalNormalMobCount =
                        statistics.SmallMonsterStatistics;
                    dailyFarmingData.TravelsDiaryDetailManagerUpdateTime =
                        DateTime.Parse(actionItems.Last().Time);
                    FarmingStatsRecorder.debugInfo(
                        $"札记当天数据：[精英：{dailyFarmingData.MiyousheTotalEliteMobCount}," +
                        $"小怪：{dailyFarmingData.MiyousheTotalNormalMobCount}," +
                        $"{dailyFarmingData.TravelsDiaryDetailManagerUpdateTime}]");
                }
                else
                {
                    logger.LogError("米游社旅行札记未有数据！");
                }
            }
            catch (Exception exception)
            {
                logger.LogError(exception, "米游社数据更新失败，请检查cookie是否过期");
            }
        }

        dailyFarmingData ??= FarmingStatsRecorder.ReadDailyFarmingData();
        dailyFarmingData.LastMiyousheUpdateTime = DateTime.Now;
        FarmingStatsRecorder.SaveDailyData(dailyFarmingData.FilePath, dailyFarmingData);
    }
}
