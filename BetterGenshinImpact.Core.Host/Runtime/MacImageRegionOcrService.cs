using BetterGenshinImpact.Core.Adapters;
using BetterGenshinImpact.Core.Recognition;
using BetterGenshinImpact.Core.Recognition.OCR;
using BetterGenshinImpact.Core.Recognition.ONNX;
using BetterGenshinImpact.Core.Runtime.Portable;
using BetterGenshinImpact.GameTask.AutoPick;
using Microsoft.Extensions.Logging;
using OpenCvSharp;
using BetterGenshinImpact.Core.Abstractions.Recognition;
using BetterGenshinImpact.Core.Recognition.ONNX.SVTR;

namespace BetterGenshinImpact.Core.Host.Runtime;

/// <summary>Lazy real Paddle OCR composition for ImageRegion on macOS.</summary>
public sealed class MacImageRegionOcrService : IOcrService, IDisposable
{
    private readonly BgiOnnxFactory _onnxFactory;
    private readonly Lazy<OcrFactory> _factory;

    public MacImageRegionOcrService(RuntimeLayout layout, ILogger<BgiOnnxFactory> logger)
    {
        _onnxFactory = new BgiOnnxFactory(
            new CpuOnnxRuntimePlatform(new ModelRootPathResolver(layout.RootPath)));
        _factory = new Lazy<OcrFactory>(() =>
        {
            var resourceResolver = new OcrResourcePathResolver(layout.RootPath);
            var runtimeConfig = new MacCoreRuntimeAdapter(
                new AutoPickConfig(), PaddleOcrModelConfig.V5Auto, "zh-CN");
            return new OcrFactory(logger, _onnxFactory, runtimeConfig, resourceResolver);
        }, LazyThreadSafetyMode.ExecutionAndPublication);
    }

    public string Ocr(Mat mat) => _factory.Value.Service.Ocr(mat);
    public string OcrWithoutDetector(Mat mat) => _factory.Value.Service.OcrWithoutDetector(mat);
    public OcrResult OcrResult(Mat mat) => _factory.Value.Service.OcrResult(mat);
    public BgiYoloPredictor CreateYoloPredictor(BgiOnnxModel model) =>
        _onnxFactory.CreateYoloPredictor(model);
    public BgiOnnxFactory OnnxFactory => _onnxFactory;

    public IPaddleAutoPickTextRecognizer CreatePaddleAutoPickTextRecognizer() =>
        new PaddleAutoPickTextRecognizer(this);

    public IYapAutoPickTextRecognizer CreateYapAutoPickTextRecognizer(RuntimeLayout layout) =>
        new LazyYapAutoPickTextRecognizer(() => new YapAutoPickTextRecognizer(
            TextInferenceFactory.Create(
                OcrEngineTypes.YapModel, _onnxFactory, new OcrResourcePathResolver(layout.RootPath))));

    public void Dispose()
    {
        if (_factory.IsValueCreated)
            _factory.Value.Dispose();
    }

    private sealed class LazyYapAutoPickTextRecognizer(Func<IYapAutoPickTextRecognizer> factory)
        : IYapAutoPickTextRecognizer
    {
        private readonly Lazy<IYapAutoPickTextRecognizer> _recognizer = new(factory);
        public string Recognize(Mat textRegion) => _recognizer.Value.Recognize(textRegion);
    }
}
