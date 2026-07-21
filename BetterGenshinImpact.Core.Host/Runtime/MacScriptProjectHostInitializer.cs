using BetterGenshinImpact.Core.Script.Dependence;
using BetterGenshinImpact.Core.Script.Project;
using BetterGenshinImpact.Core.Script.Utils;
using BetterGenshinImpact.Core.Script.Dependence.Model;
using BetterGenshinImpact.Core.Recognition;
using BetterGenshinImpact.Core.BgiVision;
using BetterGenshinImpact.GameTask.AutoFight;
using BetterGenshinImpact.GameTask.AutoFight.Model;
using BetterGenshinImpact.GameTask.AutoPathing;
using BetterGenshinImpact.GameTask.AutoSkip;
using BetterGenshinImpact.GameTask.Model.Area;
using Microsoft.ClearScript;
using OpenCvSharp;

namespace BetterGenshinImpact.Core.Host.Runtime;

/// <summary>
/// Registers the upstream host objects whose real shared implementations are composed on macOS.
/// Unsupported upstream objects are added only when their complete source slice is linked.
/// </summary>
public sealed class MacScriptProjectHostInitializer(
    IScriptGroupExecutionServices executionServices) : IScriptProjectHostInitializer
{
    public void Initialize(IScriptEngine engine, string workDir, string[] searchPaths, object? config)
    {
        ArgumentNullException.ThrowIfNull(engine);
        engine.AddHostObject("log", new Log());
        engine.AddHostObject("keyMouseScript", new KeyMouseScript(workDir));
        engine.AddHostObject("pathingScript", new AutoPathingScript(workDir, config, executionServices));
        engine.AddHostObject("genshin", new Genshin());
        engine.AddHostObject("dispatcher", new Dispatcher(config ?? new object()));
        engine.AddHostObject("file", new LimitedFile(workDir));
        engine.AddHostObject("http", new Http());
        engine.AddHostObject("notification", new Notification());
        engine.AddHostType("ServerTime", typeof(ServerTime));
        engine.AddHostType("CancellationTokenSource", typeof(CancellationTokenSource));
        engine.AddHostType("CancellationToken", typeof(CancellationToken));
        engine.AddHostType("Mat", typeof(Mat));
        engine.AddHostType("Point2f", typeof(Point2f));
        engine.AddHostType("RecognitionObject", typeof(RecognitionObject));
        engine.AddHostType("BvPage", typeof(BvPage));
        engine.AddHostType("BvLocator", typeof(BvLocator));
        engine.AddHostType("BvImage", typeof(BvImage));
        engine.AddHostType("DesktopRegion", typeof(DesktopRegion));
        engine.AddHostType("GameCaptureRegion", typeof(GameCaptureRegion));
        engine.AddHostType("ImageRegion", typeof(ImageRegion));
        engine.AddHostType("Region", typeof(Region));
        engine.AddHostType("CombatScenes", typeof(CombatScenes));
        engine.AddHostType("Avatar", typeof(Avatar));
        engine.AddHostObject("OpenCvSharp", new HostTypeCollection("OpenCvSharp"));
        engine.AddHostType("AutoFightParam", typeof(AutoFightParam));
        engine.AddHostType("AutoSkipConfig", typeof(AutoSkipConfig));
        engine.AddHostType("RealtimeTimer", typeof(RealtimeTimer));
        engine.AddHostType("SoloTask", typeof(SoloTask));
        engine.AddHostObject("strategyFile", new StrategyFile());
        engine.AddHostObject("host", new CustomHostFunctions());
        engine.AddHostType(typeof(Task));
        GlobalMethod.AddToScriptEngine(engine);

        engine.DocumentSettings.AccessFlags = DocumentAccessFlags.AllowCategoryMismatch;
        var normalizedPaths = searchPaths.Select(path => ScriptUtils.NormalizePath(workDir, path)).ToArray();
        if (normalizedPaths.Length > 0)
            engine.DocumentSettings.SearchPath = string.Join(';', normalizedPaths);
    }

    public void SetGameMetrics(int width, int height) => GlobalMethod.SetGameMetrics(width, height);
}
