using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.Core.Recognition.OCR;
using BetterGenshinImpact.GameTask.AutoArtifactSalvage;
using BetterGenshinImpact.GameTask.Common.Job;
using BetterGenshinImpact.GameTask.Model.Area;
using BetterGenshinImpact.GameTask.Model.GameUI;
using BetterGenshinImpact.Helpers.Extensions;
using BetterGenshinImpact.View.Drawable;
using Microsoft.Extensions.Logging;
using Microsoft.ML.OnnxRuntime;
using Microsoft.ML.OnnxRuntime.Tensors;
using OpenCvSharp;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using static BetterGenshinImpact.GameTask.Common.TaskControl;

namespace BetterGenshinImpact.GameTask.GetGridIcons;

/// <summary>
/// 获取Grid界面的物品图标
/// </summary>
public class GridIconsAccuracyTestTask : ISoloTask
{
    private readonly ILogger logger = App.GetLogger<GetGridIconsTask>();
    private CancellationToken ct;

    public string Name => "获取Grid界面物品图标独立任务";

    private readonly int? maxNumToTest;

    private readonly GridScreenName gridScreenName;

    public GridIconsAccuracyTestTask(GridScreenName gridScreenName, int? maxNumToTest = null)
    {
        this.gridScreenName = gridScreenName;
        this.maxNumToTest = maxNumToTest;
    }

    /// <summary>
    /// 加载图标识别模型
    /// </summary>
    /// <param name="prototypes">原型向量</param>
    /// <returns>推理会话</returns>
    /// <exception cref="Exception"></exception>
    public static InferenceSession LoadModel(out Dictionary<string, float[]> prototypes)
        => GridIconClassifier.LoadModel(out prototypes);

    public async Task Start(CancellationToken ct)
    {
        this.ct = ct;

        switch (this.gridScreenName)
        {
            case GridScreenName.Weapons:
            case GridScreenName.Artifacts:
            case GridScreenName.CharacterDevelopmentItems:
            case GridScreenName.Food:
            case GridScreenName.Materials:
            case GridScreenName.Gadget:
            case GridScreenName.Quest:
            case GridScreenName.PreciousItems:
            case GridScreenName.Furnishings:
                await new ReturnMainUiTask().Start(ct);
                await AutoArtifactSalvageTask.OpenInventory(this.gridScreenName, this.logger, this.ct);
                break;
            default:
                logger.LogInformation("{name}暂不支持自动打开，请提前手动打开界面", gridScreenName.GetDescription());
                break;
        }

        using InferenceSession session = LoadModel(out Dictionary<string, float[]> prototypes);

        int count = this.maxNumToTest ?? int.MaxValue;
        double total_acc = 0.0;
        double total_count = 0;

        GridScreen gridScreen = new GridScreen(GridParams.Templates[this.gridScreenName], this.logger, this.ct);
        gridScreen.OnAfterTurnToNewPage += GridScreen.DrawItemsAfterTurnToNewPage;
        gridScreen.OnBeforeScroll += () => VisionContext.Instance().DrawContent.ClearAll();
        try
        {
            await foreach ((ImageRegion pageRegion, Rect itemRect) in gridScreen)
            {
                using ImageRegion itemRegion = pageRegion.DeriveCrop(itemRect);
                itemRegion.Click();
                Task task1 = Delay(300, ct);

                // 用模型推理得到的结果
                Task<(string?, int)> task2 = Task.Run(() =>
                {
                    using Mat icon = itemRegion.SrcMat.GetGridIcon();
                    return Infer(icon, session, prototypes);
                }, ct);

                await Task.WhenAll(task1, task2);
                (string?, int) result = task2.Result;
                string? predName = result.Item1;
                int predStarNum = result.Item2;

                // 用CV方法得到的结果
                using var ra1 = CaptureToRectArea();
                using ImageRegion nameRegion = ra1.DeriveCrop(new Rect((int)(ra1.Width * 0.682), (int)(ra1.Width * 0.0625), (int)(ra1.Width * 0.256), (int)(ra1.Width * 0.03125)));
                var ocrResult = OcrFactory.Paddle.OcrResult(nameRegion.SrcMat);
                string itemName = ocrResult.Text;

                using ImageRegion starRegion = ra1.DeriveCrop(new Rect((int)(ra1.Width * 0.682), (int)(ra1.Width * 0.1823), (int)(ra1.Width * 0.105), (int)(ra1.Width * 0.02345)));
                int itemStarNum = GetGridIconsTask.GetStars(starRegion.SrcMat);

                // 统计结果
                total_count++;
                if (predName == null)
                {
                    logger.LogInformation($"模型没有识别，应为：{itemName}|{itemStarNum}星，❌，正确率{total_acc / total_count:0.00}");
                }
                else if (itemName.Contains(predName) && predStarNum == itemStarNum)
                {
                    total_acc++;
                    logger.LogInformation($"{predName}|{predStarNum}星，✔，正确率{total_acc / total_count:0.00}");
                }
                else
                {
                    logger.LogInformation($"{predName}|{predStarNum}星，应为：{itemName}|{itemStarNum}星，❌，正确率{total_acc / total_count:0.00}");
                }

                count--;
                if (count <= 0)
                {
                    logger.LogInformation("检查次数已耗尽");
                    break;
                }
            }
        }
        finally
        {
            VisionContext.Instance().DrawContent.ClearAll();
        }
    }

    /// <summary>
    /// 请自行裁剪缩放到125*125尺寸
    /// </summary>
    /// <param name="mat"></param>
    /// <param name="session"></param>
    /// <param name="prototypes"></param>
    /// <returns>(预测名称, 预测星级)</returns>
    /// <exception cref="Exception"></exception>
    public static (string?, int) Infer(Mat mat, InferenceSession session, Dictionary<string, float[]> prototypes)
        => GridIconClassifier.Infer(mat, session, prototypes);
}
