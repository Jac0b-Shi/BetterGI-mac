using System;
using System.Threading;
using BetterGenshinImpact.Core.Recognition.OCR;
using BetterGenshinImpact.Core.Recognition.ONNX;
using BetterGenshinImpact.GameTask.AutoFight;
using BetterGenshinImpact.GameTask.AutoFight.Config;
using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.Model;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace BetterGenshinImpact.Core.Runtime.Windows;

public sealed class WindowsAutoFightRuntimePlatform : IAutoFightRuntimePlatform
{
    public ISystemInfo SystemInfo => TaskContext.Instance().SystemInfo;
    public AutoFightConfig AutoFightConfig => TaskContext.Instance().Config.AutoFightConfig;
    public IOcrService OcrService => OcrFactory.Paddle;
    public double DpiScale => TaskContext.Instance().DpiScale;
    public int CombatMacroPriority => TaskContext.Instance().Config.MacroConfig.CombatMacroPriority;
    public ILogger<T> GetLogger<T>() => App.GetLogger<T>();
    public BgiYoloPredictor CreateYoloPredictor(BgiOnnxModel model) =>
        App.ServiceProvider.GetRequiredService<BgiOnnxFactory>().CreateYoloPredictor(model);
    public IDisposable UseConfig(AutoFightConfig config)
    {
        ArgumentNullException.ThrowIfNull(config);
        var allConfig = TaskContext.Instance().Config;
        var original = allConfig.AutoFightConfig;
        allConfig.AutoFightConfig = config;
        return new ConfigScope(() => allConfig.AutoFightConfig = original);
    }

    private sealed class ConfigScope(Action restore) : IDisposable
    {
        private Action? _restore = restore;
        public void Dispose() => Interlocked.Exchange(ref _restore, null)?.Invoke();
    }
}
