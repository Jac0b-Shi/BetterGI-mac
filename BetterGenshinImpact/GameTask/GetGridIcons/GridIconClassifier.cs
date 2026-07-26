using BetterGenshinImpact.Core.Config;
using Microsoft.ML.OnnxRuntime;
using Microsoft.ML.OnnxRuntime.Tensors;
using OpenCvSharp;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

namespace BetterGenshinImpact.GameTask.GetGridIcons;

public static class GridIconClassifier
{
    public static InferenceSession LoadModel(out Dictionary<string, float[]> prototypes)
    {
        var session = new InferenceSession(Global.Absolute(@"Assets\Model\Item\gridIcon.onnx"));
        var metadata = session.ModelMetadata;
        if (!metadata.CustomMetadataMap.TryGetValue("prefix_list", out string? prefixListJson))
            throw new Exception("模型文件缺少prefix_list");

        _ = System.Text.Json.JsonSerializer.Deserialize<List<string>>(prefixListJson)
            ?? throw new Exception("模型prefix_list无效");
        var allLines = File.ReadLines(Global.Absolute(@"Assets\Model\Item\items.csv")).Skip(1);
        prototypes = new Dictionary<string, float[]>();
        foreach (var line in allLines)
        {
            var columns = line.Split(',').ToArray();
            var bytes = Convert.FromBase64String(columns[1]);
            var flatData = new float[bytes.Length / sizeof(float)];
            Buffer.BlockCopy(bytes, 0, flatData, 0, bytes.Length);
            prototypes.Add(columns[0], flatData);
        }
        return session;
    }

    public static (string?, int) Infer(
        Mat mat,
        InferenceSession session,
        Dictionary<string, float[]> prototypes)
    {
        if (mat.Size().Width != 125 || mat.Size().Height != 125)
            throw new ArgumentOutOfRangeException(nameof(mat), "输入图像尺寸应为125*125");

        using var rgb = mat.CvtColor(ColorConversionCodes.BGR2RGB);
        var tensor = new DenseTensor<float>(new[] { 1, 3, rgb.Height, rgb.Width });
        for (var y = 0; y < rgb.Height; y++)
        for (var x = 0; x < rgb.Width; x++)
        {
            tensor[0, 0, y, x] = rgb.At<Vec3b>(y, x)[0] / 255f;
            tensor[0, 1, y, x] = rgb.At<Vec3b>(y, x)[1] / 255f;
            tensor[0, 2, y, x] = rgb.At<Vec3b>(y, x)[2] / 255f;
        }

        var inputs = new List<NamedOnnxValue>
            { NamedOnnxValue.CreateFromTensor("input_image", tensor) };
        using var results = session.Run(inputs);
        var featureMatrix = results[0].AsEnumerable<float>().ToArray();
        string? predictedName = null;
        double? minimumDistance = null;
        foreach (var prototype in prototypes)
        {
            double distance = 0;
            for (var i = 0; i < 64; i++)
                distance += Math.Pow(prototype.Value[i] - featureMatrix[i], 2f);
            if (minimumDistance is null || distance < minimumDistance)
            {
                minimumDistance = distance;
                if (minimumDistance < 10 * 10)
                    predictedName = prototype.Key;
            }
        }
        if (minimumDistance is null)
            throw new Exception("特征数据为空");

        var starScores = results[2].AsEnumerable<float>().ToList();
        var predictedStar = starScores.IndexOf(starScores.Max());
        return (predictedName, predictedStar);
    }
}
