using BetterGenshinImpact.GameTask.Common;
using BetterGenshinImpact.GameTask.Common.BgiVision;
using Microsoft.Extensions.Logging;
using System;
using System.Threading;

namespace BetterGenshinImpact.GameTask.Macro;

public enum DialogButtonType
{
    Confirm,
    Cancel,
}

public static class DialogButtonClickMacro
{
    public static bool Done(
        DialogButtonType buttonType,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        using var capture = TaskControl.CaptureToRectArea();
        cancellationToken.ThrowIfCancellationRequested();
        var clicked = buttonType switch
        {
            DialogButtonType.Confirm => Bv.ClickConfirmButton(capture),
            DialogButtonType.Cancel => Bv.ClickCancelButton(capture),
            _ => throw new ArgumentOutOfRangeException(nameof(buttonType)),
        };
        TaskControl.Logger.LogInformation(
            "触发快捷点击原神内{Btn}按钮：{Result}",
            buttonType == DialogButtonType.Confirm ? "确认" : "取消",
            clicked ? "成功" : "未找到按钮图片");
        return clicked;
    }
}
