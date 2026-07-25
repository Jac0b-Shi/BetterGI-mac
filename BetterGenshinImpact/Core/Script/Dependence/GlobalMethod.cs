using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.GameTask.Model.Area;
using Microsoft.ClearScript;
using System;
using System.Threading;
using System.Threading.Tasks;

namespace BetterGenshinImpact.Core.Script.Dependence;

/// <summary>
/// BetterGI JavaScript 全局 API。业务参数校验和坐标契约保留在共享源码中，
/// 输入、截图、剪贴板及窗口坐标转换由平台 runtime 完整实现。
/// </summary>
public static partial class GlobalMethod
{
    private static IGlobalMethodRuntime? _runtime;
    private static int _gameWidth = 1920;
    private static int _gameHeight = 1080;
    private static double _dpi = 1;

    public static void Configure(IGlobalMethodRuntime runtime)
    {
        ArgumentNullException.ThrowIfNull(runtime);
        if (Interlocked.CompareExchange(ref _runtime, runtime, null) is not null)
            throw new InvalidOperationException("GlobalMethod runtime has already been configured.");
    }

    private static IGlobalMethodRuntime Runtime => Volatile.Read(ref _runtime)
        ?? throw new InvalidOperationException("GlobalMethod runtime is not composed.");

    public static Task Sleep(int millisecondsTimeout) =>
        Task.Delay(millisecondsTimeout, Runtime.CancellationToken);

    public static string GetVersion() => Global.Version;

    public static void KeyDown(string key) => Runtime.KeyDown(key);
    public static void KeyUp(string key) => Runtime.KeyUp(key);
    public static void KeyPress(string key) => Runtime.KeyPress(key);

    public static void SetGameMetrics(int width, int height, double dpi = 1)
    {
        if (width * 9 != height * 16)
            throw new ArgumentException("游戏分辨率必须是16:9的分辨率");
        _gameWidth = width;
        _gameHeight = height;
        _dpi = dpi;
    }

    public static double[] GetGameMetrics() => [_gameWidth, _gameHeight, _dpi];

    public static void MoveMouseBy(int x, int y)
    {
        x = (int)(x * Runtime.DpiScale / _dpi);
        y = (int)(y * Runtime.DpiScale / _dpi);
        Runtime.MoveMouseBy(x, y);
    }

    public static void MoveMouseTo(int x, int y)
    {
        if (x < 0 || x > _gameWidth || y < 0 || y > _gameHeight)
            throw new ArgumentException("鼠标坐标超出游戏窗口范围");
        Runtime.MoveMouseToGameCoordinate(x, y, _gameWidth, _gameHeight);
    }

    public static void Click(int x, int y)
    {
        if (x < 0 || x > _gameWidth || y < 0 || y > _gameHeight)
            throw new ArgumentException("鼠标坐标超出游戏窗口范围");
        Runtime.ClickGameCoordinate(x, y, _gameWidth, _gameHeight);
    }

    public static void LeftButtonClick() => Runtime.LeftButtonClick();
    public static void LeftButtonDown() => Runtime.LeftButtonDown();
    public static void LeftButtonUp() => Runtime.LeftButtonUp();
    public static void RightButtonClick() => Runtime.RightButtonClick();
    public static void RightButtonDown() => Runtime.RightButtonDown();
    public static void RightButtonUp() => Runtime.RightButtonUp();
    public static void MiddleButtonClick() => Runtime.MiddleButtonClick();
    public static void MiddleButtonDown() => Runtime.MiddleButtonDown();
    public static void MiddleButtonUp() => Runtime.MiddleButtonUp();
    public static void VerticalScroll(int scrollAmountInClicks) => Runtime.VerticalScroll(scrollAmountInClicks);

    public static ImageRegion CaptureGameRegion() => Runtime.CaptureGameRegion();
    public static string[] GetAvatars() => Runtime.GetAvatars();
    public static void InputText(string text)
    {
        if (!string.IsNullOrEmpty(text)) Runtime.InputText(text);
    }

    /// <summary>
    /// Registers BetterGI's canonical JavaScript global functions. Both Windows
    /// EngineExtend and the macOS host use this single list so names cannot drift.
    /// </summary>
    public static void AddToScriptEngine(IScriptEngine engine)
    {
        ArgumentNullException.ThrowIfNull(engine);
#pragma warning disable CS8974
        engine.AddHostObject("sleep", Sleep);
        engine.AddHostObject("getVersion", GetVersion);
        engine.AddHostObject("keyDown", KeyDown);
        engine.AddHostObject("keyUp", KeyUp);
        engine.AddHostObject("keyPress", KeyPress);
        engine.AddHostObject("setGameMetrics", SetGameMetrics);
        engine.AddHostObject("getGameMetrics", GetGameMetrics);
        engine.AddHostObject("moveMouseBy", MoveMouseBy);
        engine.AddHostObject("moveMouseTo", MoveMouseTo);
        engine.AddHostObject("click", Click);
        engine.AddHostObject("leftButtonClick", LeftButtonClick);
        engine.AddHostObject("leftButtonDown", LeftButtonDown);
        engine.AddHostObject("leftButtonUp", LeftButtonUp);
        engine.AddHostObject("rightButtonClick", RightButtonClick);
        engine.AddHostObject("rightButtonDown", RightButtonDown);
        engine.AddHostObject("rightButtonUp", RightButtonUp);
        engine.AddHostObject("middleButtonClick", MiddleButtonClick);
        engine.AddHostObject("middleButtonDown", MiddleButtonDown);
        engine.AddHostObject("middleButtonUp", MiddleButtonUp);
        engine.AddHostObject("verticalScroll", VerticalScroll);
        engine.AddHostObject("captureGameRegion", CaptureGameRegion);
        engine.AddHostObject("getAvatars", GetAvatars);
        engine.AddHostObject("inputText", InputText);
#pragma warning restore CS8974
    }
}

public interface IGlobalMethodRuntime
{
    CancellationToken CancellationToken { get; }
    double DpiScale { get; }
    void KeyDown(string key);
    void KeyUp(string key);
    void KeyPress(string key);
    void MoveMouseBy(int x, int y);
    void MoveMouseToGameCoordinate(int x, int y, int gameWidth, int gameHeight);
    void ClickGameCoordinate(int x, int y, int gameWidth, int gameHeight);
    void LeftButtonClick();
    void LeftButtonDown();
    void LeftButtonUp();
    void RightButtonClick();
    void RightButtonDown();
    void RightButtonUp();
    void MiddleButtonClick();
    void MiddleButtonDown();
    void MiddleButtonUp();
    void VerticalScroll(int scrollAmountInClicks);
    ImageRegion CaptureGameRegion();
    string[] GetAvatars();
    void InputText(string text);
}
