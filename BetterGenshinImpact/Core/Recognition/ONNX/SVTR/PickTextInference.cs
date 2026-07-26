using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.Core.Abstractions.Runtime;
using Microsoft.ML.OnnxRuntime;
using Microsoft.ML.OnnxRuntime.Tensors;
using OpenCvSharp;
using System;
using System.Buffers;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;
using BetterGenshinImpact.Core.Recognition.OCR.Engine;
using Newtonsoft.Json;

namespace BetterGenshinImpact.Core.Recognition.ONNX.SVTR;

/// <summary>
///     来自于 Yap 的拾取文字识别
///     https://github.com/Alex-Beng/Yap
/// </summary>
public class PickTextInference : ITextInference
{
    /// <summary>
    /// Manifest-registered Yap dictionary relative path.
    /// Must match the sidecar path in model-artifacts.manifest.json.
    /// </summary>
    public const string YapDictionaryRelativePath =
        "Assets/Model/Yap/index_2_word.json";

    private readonly InferenceSession _session;
    private readonly Dictionary<int, string> _wordDictionary;

#if BGI_PLATFORM_MAC
    public PickTextInference(BgiOnnxFactory onnxFactory, IOcrResourcePathResolver resourceResolver)
    {
        ArgumentNullException.ThrowIfNull(onnxFactory);
        ArgumentNullException.ThrowIfNull(resourceResolver);
        _session = onnxFactory.CreateInferenceSession(BgiOnnxModel.YapModelTraining, true);
        _wordDictionary = LoadWordDictionary(resourceResolver.ResolveSidecarPath(YapDictionaryRelativePath));
    }
#else
    public PickTextInference(BgiOnnxFactory onnxFactory)
    {
        ArgumentNullException.ThrowIfNull(onnxFactory);
        _session = onnxFactory.CreateInferenceSession(BgiOnnxModel.YapModelTraining, true);
        _wordDictionary = LoadWordDictionary(Global.Absolute(@"Assets\Model\Yap\index_2_word.json"));
    }
#endif

    private static Dictionary<int, string> LoadWordDictionary(string wordJsonPath)
    {
        if (!File.Exists(wordJsonPath)) throw new FileNotFoundException("Yap字典文件不存在", wordJsonPath);
        var json = File.ReadAllText(wordJsonPath);
        return JsonConvert.DeserializeObject<Dictionary<int, string>>(json) ??
                          throw new InvalidDataException("index_2_word.json deserialize failed");
    }

    public string Inference(Mat mat)
    {
        long startTime = Stopwatch.GetTimestamp();
        // 将输入数据调整为 (1, 1, 32, 384) 形状的张量
        var reshapedInputData  = OcrUtils.ToTensorYapDnn(mat, out var owner);

        IDisposableReadOnlyCollection<DisposableNamedOnnxValue> results;

        using (owner)
        {
            // 创建输入 NamedOnnxValue, 运行模型推理
            results = _session.Run([NamedOnnxValue.CreateFromTensor("input", reshapedInputData)]);
        }

        using (results)
        {
            // 获取输出数据
            var boxes = results[0].AsTensor<float>();

            var ans = new StringBuilder();
            var lastWord = default(string);
            for (var i = 0; i < boxes.Dimensions[0]; i++)
            {
                var maxIndex = 0;
                var maxValue = -1.0;
                for (var j = 0; j < _wordDictionary.Count; j++)
                {
                    var value = boxes[[i, 0, j]];
                    if (value > maxValue)
                    {
                        maxValue = value;
                        maxIndex = j;
                    }
                }

                var word = _wordDictionary[maxIndex];
                if (word != lastWord && word != "|")
                {
                    ans.Append(word);
                }

                lastWord = word;
            }

            TimeSpan time = Stopwatch.GetElapsedTime(startTime);
            string result = ans.ToString();
            Debug.WriteLine($"Yap模型识别 耗时{time.TotalMilliseconds}ms 结果: {result}");
            return result;
        }
    }


    [Obsolete("使用CV DNN替代")]
    public static Tensor<float> ToTensorUnsafe(Mat src, out IMemoryOwner<float> tensorMemoryOwnser)
    {
        var channels = src.Channels();
        var nRows = src.Rows;
        var nCols = src.Cols * channels;
        if (src.IsContinuous())
        {
            nCols *= nRows;
            nRows = 1;
        }

        //var inputData = new float[nCols];
        tensorMemoryOwnser = MemoryPool<float>.Shared.Rent(nCols);
        var memory = tensorMemoryOwnser.Memory[..nCols];
        unsafe
        {
            for (var i = 0; i < nRows; i++)
            {
                var b = (byte*)src.Ptr(i);
                for (var j = 0; j < nCols; j++)
                {
                    memory.Span[j] = b[j] / 255f;
                }
            }
        }

        return new DenseTensor<float>(memory, [1, 1, 32, 384]);
    }
}
