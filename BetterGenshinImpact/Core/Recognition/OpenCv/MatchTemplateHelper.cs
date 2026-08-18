using OpenCvSharp;
using System;
using System.Collections.Generic;
#if !BGI_PLATFORM_MAC
using Microsoft.Extensions.Logging;
#endif

namespace BetterGenshinImpact.Core.Recognition.OpenCv;

/// <summary>
///     模板匹配辅助方法
/// </summary>
public class MatchTemplateHelper
{
#if !BGI_PLATFORM_MAC
    private static readonly ILogger<MatchTemplateHelper> _logger = App.GetLogger<MatchTemplateHelper>();
#endif

    /// <summary>
    ///  模板匹配
    /// </summary>
    /// <param name="srcMat">原图像</param>
    /// <param name="dstMat">模板</param>
    /// <param name="matchMode">匹配方式</param>
    /// <param name="maskMat">遮罩</param>
    /// <param name="threshold">阈值</param>
    /// <returns>左上角的标点,由于(0,0)点作为未匹配的结果，所以不能做完全相同的模板匹配</returns>
    public static Point MatchTemplate(Mat srcMat, Mat dstMat, TemplateMatchModes matchMode, Mat? maskMat = null, double threshold = 0.8)
    {
        return FindBestMatch(srcMat, dstMat, matchMode, maskMat, threshold)?.Location ?? default;
    }

    /// <summary>
    ///     模板匹配多个结果
    ///     从一次匹配的结果矩阵中提取候选，并在当前模板内执行 NMS
    /// </summary>
    /// <param name="srcMat"></param>
    /// <param name="dstMat"></param>
    /// <param name="maskMat"></param>
    /// <param name="threshold"></param>
    /// <param name="maxCount"></param>
    /// <returns></returns>
    [Obsolete]
    public static List<Point> MatchTemplateMulti(Mat srcMat, Mat dstMat, Mat? maskMat = null, double threshold = 0.8, int maxCount = 8)
    {
        var matches = FindMatches(srcMat, dstMat, TemplateMatchModes.CCoeffNormed, maskMat, threshold, maxCount);
        var points = new List<Point>(matches.Count);
        foreach (var match in matches)
        {
            points.Add(match.Location);
        }

        return points;
    }

    [Obsolete]
    public static List<Point> MatchTemplateMulti(Mat srcMat, Mat dstMat, double threshold)
    {
        return MatchTemplateMulti(srcMat, dstMat, null, threshold);
    }

    /// <summary>
    ///     在一张图中查找多个模板
    /// </summary>
    /// <param name="srcMat"></param>
    /// <param name="imgSubDictionary"></param>
    /// <param name="threshold"></param>
    /// <returns></returns>
    public static Dictionary<string, List<Point>> MatchMultiPicForOnePic(Mat srcMat, Dictionary<string, Mat> imgSubDictionary, double threshold = 0.8)
    {
        var dictionary = new Dictionary<string, List<Point>>();
        foreach (var kvp in imgSubDictionary)
        {
            var matches = FindMatches(srcMat, kvp.Value, TemplateMatchModes.CCoeffNormed, null, threshold, -1);
            var list = new List<Point>(matches.Count);
            foreach (var match in matches)
            {
                list.Add(match.Location);
            }

            dictionary.Add(kvp.Key, list);
        }

        return dictionary;
    }

    /// <summary>
    ///     在一张图中查找多个模板
    /// </summary>
    /// <param name="srcMat"></param>
    /// <param name="imgSubList"></param>
    /// <param name="threshold"></param>
    /// <returns></returns>
    public static List<Rect> MatchMultiPicForOnePic(Mat srcMat, IReadOnlyList<Mat> imgSubList, double threshold = 0.8)
    {
        List<Rect> list = [];
        foreach (var sub in imgSubList)
        {
            var matches = FindMatches(srcMat, sub, TemplateMatchModes.CCoeffNormed, null, threshold, -1);
            foreach (var match in matches)
            {
                list.Add(new Rect(match.Location.X, match.Location.Y, sub.Width, sub.Height));
            }
        }

        return list;
    }

    /// <summary>
    ///     在一张图中查找一个个模板
    /// </summary>
    /// <param name="srcMat"></param>
    /// <param name="dstMat"></param>
    /// <param name="maskMat"></param>
    /// <param name="threshold"></param>
    /// <returns></returns>
    public static List<Rect> MatchOnePicForOnePic(Mat srcMat, Mat dstMat, Mat? maskMat = null, double threshold = 0.8)
    {
        return MatchOnePicForOnePic(srcMat, dstMat, TemplateMatchModes.CCoeffNormed, maskMat, threshold);
    }

    /// <summary>
    ///    在一张图中查找一个个模板
    /// </summary>
    /// <param name="srcMat"></param>
    /// <param name="dstMat"></param>
    /// <param name="matchMode"></param>
    /// <param name="maskMat"></param>
    /// <param name="threshold"></param>
    /// <param name="maxCount"></param>
    /// <returns></returns>
    public static List<Rect> MatchOnePicForOnePic(Mat srcMat, Mat dstMat, TemplateMatchModes matchMode, Mat? maskMat, double threshold, int maxCount = -1)
    {
        var matches = FindMatches(srcMat, dstMat, matchMode, maskMat, threshold, maxCount);
        var list = new List<Rect>(matches.Count);
        foreach (var match in matches)
        {
            list.Add(new Rect(match.Location.X, match.Location.Y, dstMat.Width, dstMat.Height));
        }

        return list;
    }

    internal readonly record struct TemplateMatchResult(Point Location, double Score);

    /// <summary>
    ///     返回源图中的最佳模板匹配，并保留匹配得分。
    /// </summary>
    internal static TemplateMatchResult? FindBestMatch(
        Mat srcMat,
        Mat template,
        TemplateMatchModes matchMode,
        Mat? mask,
        double threshold)
    {
        var matches = FindMatches(srcMat, template, matchMode, mask, threshold, 1);
        return matches.Count == 0 ? null : matches[0];
    }

    /// <summary>
    ///     在源图中匹配指定模板，从响应矩阵中按分数顺序提取候选，并通过 NMS 去除重复结果。
    /// </summary>
    /// <param name="srcMat">待搜索的源图。</param>
    /// <param name="template">需要匹配的模板图。</param>
    /// <param name="matchMode">OpenCV 模板匹配模式。</param>
    /// <param name="mask">模板掩码；为 <see langword="null"/> 时模板全部区域参与匹配。</param>
    /// <param name="threshold">匹配阈值，值越大筛选越严格。</param>
    /// <param name="maxCount">最大结果数；小于 0 时根据源图与模板面积自动估算。</param>
    /// <returns>按匹配质量从优到劣排列的模板左上角坐标及分数。</returns>
    internal static List<TemplateMatchResult> FindMatches(
        Mat srcMat,
        Mat template,
        TemplateMatchModes matchMode,
        Mat? mask,
        double threshold,
        int maxCount)
    {
        var matches = new List<TemplateMatchResult>();
        try
        {
            // 模板必须能够完整地在源图中滑动，否则 OpenCV 无法生成有效的匹配结果矩阵。
            if (srcMat.Empty() || template.Empty()
                || srcMat.Width < template.Width || srcMat.Height < template.Height)
            {
                return matches;
            }

            // 负数表示不限制明确数量，这里以源图最多能容纳的模板数量作为循环安全上限。
            if (maxCount < 0)
            {
                maxCount = srcMat.Width * srcMat.Height / template.Width / template.Height;
            }

            if (maxCount <= 0)
            {
                return matches;
            }

            // result 的每个坐标代表模板左上角放置在源图对应坐标时的匹配分数。
            using var result = new Mat();
            Cv2.MatchTemplate(srcMat, template, result, matchMode, mask!);

            if (matchMode is TemplateMatchModes.SqDiff or TemplateMatchModes.CCoeff or TemplateMatchModes.CCorr)
            {
                // 非 Normed 模式的分数没有固定范围，统一归一化到 [0, 1] 以便应用阈值。
                Cv2.Normalize(result, result, 0, 1, NormTypes.MinMax);
            }

            // 平方差模式分数越小越好；其余模式分数越大越好。
            // 对平方差使用 1 - threshold，使调用方始终可以按“阈值越大越严格”理解 threshold。
            var isLowerBetter = matchMode is TemplateMatchModes.SqDiff or TemplateMatchModes.SqDiffNormed;
            var scoreThreshold = isLowerBetter ? 1 - threshold : threshold;

            // 将通过阈值的位置标记为候选点；后续 NMS 只修改该掩码，不修改原始匹配分数。
            using var candidateMask = new Mat();
            Cv2.Compare(result, new Scalar(scoreThreshold), candidateMask,
                isLowerBetter ? CmpTypes.LE : CmpTypes.GE);

            // 搜索区域与模板完全相同时，响应矩阵只有一个元素。
            // 部分 OpenCV 版本对 1x1 掩码执行带 mask 的 MinMaxLoc 会发生原生异常，因此直接读取唯一分数。
            if (result.Width == 1 && result.Height == 1)
            {
                var rawScore = result.At<float>(0, 0);
                var passed = !float.IsNaN(rawScore)
                             && (isLowerBetter ? rawScore <= scoreThreshold : rawScore >= scoreThreshold);
                if (passed)
                {
                    var score = isLowerBetter ? 1 - rawScore : rawScore;
                    matches.Add(new TemplateMatchResult(new Point(0, 0), score));
                }

                return matches;
            }

            while (matches.Count < maxCount)
            {
                // 仅在候选掩码非零的位置中，提取当前分数最优的匹配点。
                Cv2.MinMaxLoc(result, out var minScore, out var maxScore, out var minLocation, out var maxLocation, candidateMask);
                var location = isLowerBetter ? minLocation : maxLocation;

                // 没有有效候选点时 MinMaxLoc 的位置不可再使用，结束提取。
                if (location.X < 0 || location.X >= candidateMask.Width
                    || location.Y < 0 || location.Y >= candidateMask.Height
                    || candidateMask.At<byte>(location.Y, location.X) == 0)
                {
                    break;
                }

                var rawScore = isLowerBetter ? minScore : maxScore;
                if (double.IsNaN(rawScore))
                {
                    // 忽略异常分数并移除该候选，避免下一轮重复选中。
                    candidateMask.Set(location.Y, location.X, (byte)0);
                    continue;
                }

                // 对外统一为分数越高匹配越好，平方差模式需反转原始分数方向。
                var score = isLowerBetter ? 1 - rawScore : rawScore;
                matches.Add(new TemplateMatchResult(location, score));

                // 保持旧实现的零重叠语义：任何与当前模板区域相交的候选都应被抑制。
                // AutoPick 与计数类调用方依赖这一行为避免相邻响应峰重复计数。
                SuppressOverlappingCandidates(candidateMask, location, template.Width, template.Height);
            }
        }
        catch (Exception ex)
        {
#if !BGI_PLATFORM_MAC
            _logger.LogError(ex.Message);
            _logger.LogDebug(ex, ex.Message);
#else
            _ = ex;
#endif
        }

        return matches;
    }

    /// <summary>
    ///     在候选掩码中清除所有与已选模板区域相交的候选点，避免重复返回同一目标。
    /// </summary>
    /// <param name="candidateMask">候选点掩码，非零像素表示该坐标仍可参与匹配。</param>
    /// <param name="selected">已选模板在源图中的左上角坐标。</param>
    /// <param name="templateWidth">模板宽度。</param>
    /// <param name="templateHeight">模板高度。</param>
    private static void SuppressOverlappingCandidates(
        Mat candidateMask,
        Point selected,
        int templateWidth,
        int templateHeight)
    {
        var maxDeltaX = templateWidth - 1;
        var maxDeltaY = templateHeight - 1;

        // 将搜索区域裁剪到候选掩码边界内，防止访问越界。
        var minX = Math.Max(0, selected.X - maxDeltaX);
        var maxX = Math.Min(candidateMask.Width - 1, selected.X + maxDeltaX);
        var minY = Math.Max(0, selected.Y - maxDeltaY);
        var maxY = Math.Min(candidateMask.Height - 1, selected.Y + maxDeltaY);

        for (var y = minY; y <= maxY; y++)
        {
            for (var x = minX; x <= maxX; x++)
            {
                if (HasSuppressingOverlap(selected, new Point(x, y), templateWidth, templateHeight)
                    && candidateMask.At<byte>(y, x) != 0)
                {
                    // 清零后，该坐标不会再被后续 MinMaxLoc 选中。
                    candidateMask.Set(y, x, (byte)0);
                }
            }
        }
    }

    /// <summary>
    ///     判断两个相同尺寸的模板矩形是否存在任何面积重叠。
    /// </summary>
    /// <param name="first">第一个模板矩形的左上角坐标。</param>
    /// <param name="second">第二个模板矩形的左上角坐标。</param>
    /// <param name="templateWidth">模板矩形宽度。</param>
    /// <param name="templateHeight">模板矩形高度。</param>
    /// <returns>两个矩形存在非零交集时返回 <see langword="true"/>。</returns>
    private static bool HasSuppressingOverlap(
        Point first,
        Point second,
        int templateWidth,
        int templateHeight)
    {
        // 两个矩形尺寸相同，因此重叠边长等于模板边长减去对应方向的坐标偏移。
        var overlapWidth = templateWidth - Math.Abs(first.X - second.X);
        var overlapHeight = templateHeight - Math.Abs(first.Y - second.Y);
        if (overlapWidth <= 0 || overlapHeight <= 0)
        {
            return false;
        }

        return true;
    }
}
