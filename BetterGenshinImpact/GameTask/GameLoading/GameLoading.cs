using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.Core.Recognition;
using System;
using System.Collections.Generic;
using BetterGenshinImpact.GameTask.Common;
using BetterGenshinImpact.GameTask.Common.BgiVision;
using BetterGenshinImpact.GameTask.Common.Element.Assets;
using BetterGenshinImpact.GameTask.Model.Area;
using Microsoft.Extensions.Logging;
using System.IO;
using System.Text.RegularExpressions;
using System.Linq;
using System.Threading;

namespace BetterGenshinImpact.GameTask.GameLoading;

public class GameLoadingTrigger : ITaskTrigger
{
    public static bool GlobalEnabled = true;
    
    public string Name => "自动开门";

    public bool IsEnabled { get => GlobalEnabled; set {} }

    public int Priority => 999;

    public bool IsExclusive => false;

    public bool IsBiliJudged = false;
    public bool IsBili = false;

    public bool IsBackgroundRunning => true;

    private readonly IGameLoadingRuntimePlatform _runtime;
    private readonly GenshinStartConfig _config;
    private readonly ILogger<GameLoadingTrigger> _logger;


    // private int _enterGameClickCount = 0;
    // private int _welkinMoonClickCount = 0;
    // private int _noneClickCount, _wmNoneClickCount;

    private DateTime _prevExecuteTime = DateTime.MinValue;

    private DateTime _triggerStartTime = DateTime.Now;

    private string GameServer = "";

    private string channelValue = "";

    private string FileName = "";

    private bool biliLoginClicked = false;
    private DateTime _prevAgePromptOcrTime = DateTime.MinValue;
    private List<Region> _latestLoadingOcrRegions = [];

    public GameLoadingTrigger()
    {
        _runtime = GameLoadingRuntimePlatform.Current;
        _config = _runtime.Config;
        _logger = _runtime.Logger;
    }

    public void InnerSetEnabled(bool enabled)
    {
        GlobalEnabled = enabled;
    }

    public void Init()
    {
        if (!_config.AutoEnterGameEnabled)
        {
            InnerSetEnabled(false);
        }

        // // 前面没有联动启动原神，这个任务也不用启动
        // if ((DateTime.Now - TaskContext.Instance().LinkedStartGenshinTime).TotalMinutes >= 5)
        // {
        //     IsEnabled = false;
        // }
        if (_config.RecordGameTimeEnabled)
        {
            FileName = Path.GetFileName(_config.InstallPath);
            if (FileName == "GenshinImpact.exe")
            {
                GameServer = "hk4e_global";
                StartStarward();
            }

            if (FileName == "YuanShen.exe")
            {
                string iniPath = Path.GetDirectoryName(_config.InstallPath) + "//config.ini";
                string iniContent;
                string pattern = @"
            ^\s*\[General\]\s*$
            (?:(?!\[).|\r?\n)*
            ^\s*channel=(\S+)
        ";

                try
                {
                    iniContent = File.ReadAllText(iniPath);
                    Regex regex = new Regex(pattern,
                        RegexOptions.Multiline | RegexOptions.IgnorePatternWhitespace | RegexOptions.IgnoreCase);
                    Match match = regex.Match(iniContent);
                    channelValue = match.Success ? match.Groups[1].Value : "";
                }
                catch (Exception e)
                {
                    _logger.LogDebug(e, "读取游戏区服配置失败");
                }

                // channelValue = 1 ： 官服
                // channelValue = 14 ： B服
                if (channelValue == "1")
                {
                    GameServer = "hk4e_cn";
                    StartStarward();
                }

                if (channelValue == "14")
                {
                    GameServer = "hk4e_bilibili";
                    StartStarward();
                }


                _logger.LogDebug("[GameLoading] 从文件读取到游戏区服：{GameServer}", GameServer);
                // 这里注册表的优先级要比读取文件低，因为使用starward安装原神不会写入注册表
                if (GameServer == null)
                {
                    GameServer = _runtime.GetInstalledGameServer();
                    _logger.LogDebug("[GameLoading] 从平台读取到游戏区服：{GameServer}", GameServer);
                    StartStarward();
                }
            }
        }
    }

    public bool StartStarward()
        => _runtime.TryStartPlaytimeTracking(GameServer);

    public string GetGameServerRegistry()
        => _runtime.GetInstalledGameServer();

    public bool IsStarwardProtocolRegistered()
        => _runtime.IsPlaytimeTrackingAvailable();

    public void OnCapture(CaptureContent content)
    {
        // 2s 一次
        if ((DateTime.Now - _prevExecuteTime).TotalMilliseconds <= 2000)
        {
            return;
        }

        _prevExecuteTime = DateTime.Now;
        // 5min 后自动停止
        if ((DateTime.Now - _triggerStartTime).TotalMinutes >= 5)
        {
            InnerSetEnabled(false);
            return;
        }
        
        // 成功进入游戏判断    
        if (Bv.IsInMainUi(content.CaptureRectArea) || Bv.IsInAnyClosableUi(content.CaptureRectArea) || Bv.IsInDomain(content.CaptureRectArea))
        {
            // _logger.LogInformation("当前在游戏主界面");
            InnerSetEnabled(false);
            return;
        }

        if ((DateTime.Now - _prevAgePromptOcrTime).TotalMilliseconds >= 1000)
        {
            _prevAgePromptOcrTime = DateTime.Now;
            _latestLoadingOcrRegions = content.CaptureRectArea.FindMulti(RecognitionObject.OcrThis);
            if (_latestLoadingOcrRegions.Any(region =>
                    region.Text.Contains("适龄") || region.Text.Contains("监护")))
            {
                // 适龄提示窗口自动关闭
                var agePopup = content.CaptureRectArea.Find(ElementRecognition.Get("BtnWhiteConfirm", content.CaptureRectArea));
                if (!agePopup.IsEmpty())
                {
                    agePopup.Click();
                    _logger.LogInformation("检测到适龄提示，自动点击确认");
                }
            }
        }
        


        // B服判断
        if (!IsBiliJudged)
        {
            try
            {
                var exePath = _config.InstallPath;
                if (!string.IsNullOrEmpty(exePath))
                {
                    var configIni = Path.Combine(Path.GetDirectoryName(exePath)!, "config.ini");
                    if (File.Exists(configIni))
                    {
                        var lines = File.ReadAllLines(configIni);
                        foreach (var line in lines)
                        {
                            var kv = line.Trim();
                            if (kv.StartsWith("channel=") && kv.EndsWith("14"))
                            {
                                IsBili = true;
                                break;
                            }
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                TaskControl.Logger.LogWarning("B服判断异常: " + ex.Message);
            }
            IsBiliJudged = true;
        }

        // 官服流程：先识别并点击顶号或切号的后一次“进入游戏”弹窗按钮
        if (!IsBili)
        {
            var extraEnterGameBtn = content.CaptureRectArea.Find(RecognitionAssets.Get("GameLoading", "ChooseEnterGame", content.CaptureRectArea));
            if (!extraEnterGameBtn.IsEmpty())
            {
                extraEnterGameBtn.Click();
                return;
            }
        }

        // 点击进入游戏按钮
        var ra = content.CaptureRectArea.Find(RecognitionAssets.Get("GameLoading", "EnterGame", content.CaptureRectArea));

        if (!ra.IsEmpty())
        {
            _runtime.BackgroundClick();
            biliLoginClicked = true;
            return;
        }

        // 只有在"进入游戏"按钮未出现时，才进行B服登录处理
        if (IsBili && !biliLoginClicked)
        {
            // B服流程：处理登录窗口
            var windowType = _runtime.GetBiliLoginWindowType();

            if (windowType != BiliLoginWindowType.None)
            {
                if (windowType == BiliLoginWindowType.Agreement)
                {
                    _runtime.ClickGame1080P(
                        960 + 70 * _runtime.DpiScale,
                        540 + 75 * _runtime.DpiScale);
                }

                if (windowType == BiliLoginWindowType.Login)
                {
                    Thread.Sleep(2000);
                    _runtime.ClickGame1080P(960, 540 + 90 * _runtime.DpiScale);
                    Thread.Sleep(2000);

                    // 检查窗口是否还存在
                    if (_runtime.GetBiliLoginWindowType() == BiliLoginWindowType.None)
                    {
                        _logger.LogInformation("B服登录完成，准备进入游戏");
                        // 添加延时确保窗口完全消失
                        Thread.Sleep(2000);
                        // 点击屏幕尝试找回焦点
                        _runtime.BackgroundClick();
                        biliLoginClicked = true;
                    }
                }
            }
        }

        if (Bv.IsInBlessingOfTheWelkinMoon(content.CaptureRectArea))
        {
            _runtime.MoveToGame1080P(100, 100);
            _runtime.BackgroundClick();
            _logger.LogDebug("[GameLoading] Click blessing of the welkin moon");
            // TaskControl.Logger.LogInformation("自动点击月卡");
            return;
        }

        // 原石
        var ysRa = content.CaptureRectArea.Find(ElementRecognition.Get("Primogem", content.CaptureRectArea));
        if (!ysRa.IsEmpty())
        {
            _runtime.MoveToGame1080P(100, 100);
            _runtime.BackgroundClick();
            _logger.LogDebug("[GameLoading] 跳过原石");
            return;
        }
    }

};
