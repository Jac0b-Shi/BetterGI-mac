using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using BetterGenshinImpact.Core.BgiVision;
using BetterGenshinImpact.GameTask.Common;
using BetterGenshinImpact.GameTask.Common.BgiVision;
using BetterGenshinImpact.GameTask.Common.Element.Assets;
using BetterGenshinImpact.GameTask.Common.Job;
using BetterGenshinImpact.GameTask.UseRedeemCode.Model;
using BetterGenshinImpact.Helpers.Extensions;
using Microsoft.Extensions.Logging;
using Rect = OpenCvSharp.Rect;

namespace BetterGenshinImpact.GameTask.UseRedeemCode;

public class UseRedemptionCodeTask : ISoloTask
{
    private readonly List<RedeemCode> _list;
    private readonly IUseRedemptionCodeRuntimePlatform _platform;
    private ILogger<UseRedemptionCodeTask> Logger => _platform.Logger;

    public UseRedemptionCodeTask(
        List<RedeemCode> list, IUseRedemptionCodeRuntimePlatform platform)
    {
        _list = list;
        _platform = platform;
    }
    
    public UseRedemptionCodeTask(
        List<string> strList, IUseRedemptionCodeRuntimePlatform platform)
    {
        _list = strList
            .Where(code => !string.IsNullOrWhiteSpace(code))
            .Select(code => new RedeemCode(code, null))
            .ToList();
        _platform = platform;
    }

    public string Name => "使用兑换码";

    public async Task Start(CancellationToken ct)
    {
        InitLog(_list);

        try
        {
            Rect captureRect = _platform.SystemInfo.ScaleMax1080PCaptureRect;

            await new ReturnMainUiTask().Start(ct);

            var page = new BvPage(ct);

            Logger.LogInformation("使用兑换码: {Msg}", "打开设置");
            // 按ESC键打开菜单
            TaskControlPlatform.Current.PressEscape();
            // 等待ESC后菜单出现
            await page.Locator(new BvImage("UseRedeemCode:esc_return_button.png")).WaitFor();
            // 点击设置按钮
            page.Click(45, 825);
            await page.Wait(1000);

            // 点击账户
            Logger.LogInformation("使用兑换码: {Msg}", "点击账户 —— 前往兑换");
            await page.GetByText("账户").WithRoi(captureRect.CutLeft(0.2)).Click();
            await page.Wait(300);

            // 点击前往兑换
            await page.GetByText("前往兑换").WithRoi(captureRect.CutRight(0.3)).Click();

            // 等待兑换码输入框出现
            await page.GetByText("兑换奖励").WaitFor();


            foreach (var redeemCode in _list)
            {
                if (string.IsNullOrEmpty(redeemCode.Code))
                {
                    continue;
                }

                await UseRedeemCode(redeemCode, page);
            }
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception ex)
        {
            Logger.LogError("使用兑换码时发生错误: {Message}", ex.Message);
            Logger.LogDebug(ex, "使用兑换码时发生错误");
            if (_platform.PropagateTaskExceptions) throw;
        }
        finally
        {
            try
            {
                _platform.ClearClipboard();
            }
            finally
            {
                await new ReturnMainUiTask().Start(ct);
            }
        }
    }

    private async Task UseRedeemCode(RedeemCode redeemCode, BvPage page)
    {
        Rect captureRect = _platform.SystemInfo.ScaleMax1080PCaptureRect;
        
        Logger.LogInformation("输入兑换码: {Code}", redeemCode.Code);
        // 将要输入的文本复制到剪贴板
        _platform.SetClipboardText(redeemCode.Code!);
        // 粘贴兑换码
        await page.GetByText("粘贴").WithRoi(captureRect.CutRight(0.5)).Click();
        // 点击兑换
        await page.Locator(ElementRecognition.Get("BtnWhiteConfirm")).Click();

        // 兑换成功
        var list = await page.GetByText("兑换成功").TryWaitFor(1000);
        if (list.Count > 0)
        {
            Logger.LogInformation("兑换码 {Code} 兑换成功", redeemCode.Code);
            // 点击确认
            await page.Locator(ElementRecognition.Get("BtnBlackConfirm")).Click();
            await page.Wait(5100);
        }
        else
        {
            Logger.LogWarning("兑换码 {Code} 兑换失败，可能是过期、错误或已被使用", redeemCode.Code);
            // 点击清除
            await page.GetByText("清除").WithRoi(captureRect.CutRight(0.5)).Click();
        }
    }


    private void InitLog(List<RedeemCode> list)
    {
        Logger.LogInformation("开始使用兑换码:");
        foreach (var redeemCode in list)
        {
            if (string.IsNullOrEmpty(redeemCode.Items))
            {
                Logger.LogInformation("{Code}", redeemCode.Code);
            }
            else
            {
                Logger.LogInformation("{Code} - {Msg}", redeemCode.Code, redeemCode.Items);
            }
        }
    }
}
