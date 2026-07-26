using BetterGenshinImpact.Core.Recognition.OCR;
using BetterGenshinImpact.GameTask.AutoBoss;
using BetterGenshinImpact.GameTask.AutoFight;
using BetterGenshinImpact.GameTask.Model;
using Microsoft.Extensions.Logging;
using NotifyService = BetterGenshinImpact.Service.Notification.Notify;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class MacAutoBossRuntimePlatform(
    Func<ISystemInfo> systemInfo,
    IOcrService ocrService,
    AutoFightConfig autoFightConfig,
    ILoggerFactory loggerFactory) : IAutoBossRuntimePlatform
{
    public ISystemInfo SystemInfo => systemInfo();
    public IOcrService OcrService => ocrService;
    public AutoFightConfig AutoFightConfig { get; } = autoFightConfig;
    public ILogger<AutoBossTask> Logger { get; } = loggerFactory.CreateLogger<AutoBossTask>();

    public void Notify(AutoBossNotification notification, string message) =>
        NotifyService.Event("AutoBoss").Success(message);
}
