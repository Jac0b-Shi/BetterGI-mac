using BetterGenshinImpact.Core.Recognition;
using Newtonsoft.Json;
using OpenCvSharp;

namespace BetterGenshinImpact.Core.Host.Runtime;

public static class RecognitionResourceSmoke
{
    private static readonly (int Width, int Height)[] CaptureSizes =
        [(1920, 1080), (1280, 720)];

    public static object Run(string runtimeRoot)
    {
        var gameTaskRoot = Path.Combine(runtimeRoot, "GameTask");
        if (!Directory.Exists(gameTaskRoot))
            throw new DirectoryNotFoundException($"Runtime GameTask root is missing: {gameTaskRoot}");

        var configCount = 0;
        var objectCount = 0;
        foreach (var filePath in Directory.EnumerateFiles(
                     gameTaskRoot, "Recognition.json", SearchOption.AllDirectories).Order())
        {
            var config = JsonConvert.DeserializeObject<RecognitionObjectJsonFile>(
                             File.ReadAllText(filePath))
                         ?? throw new InvalidDataException($"Invalid recognition config: {filePath}");
            var assetsRoot = Path.GetDirectoryName(filePath)!;
            foreach (var objectName in config.Objects.Keys.Order())
            {
                foreach (var (width, height) in CaptureSizes)
                {
                    var recognitionObject = RecognitionObjectJsonLoader.Load(
                        config, objectName, new RecognitionObjectJsonLoadContext
                        {
                            CaptureWidth = width,
                            CaptureHeight = height,
                            TemplateLoader = (template, mode) =>
                                LoadTemplate(assetsRoot, template, width, height, mode),
                        });
                    recognitionObject.TemplateImageMat?.Dispose();
                }
                objectCount++;
            }
            configCount++;
        }

        if (configCount == 0)
            throw new InvalidDataException("Packaged GameTask contains no Recognition.json files.");
        return new { recognitionConfigs = configCount, recognitionObjects = objectCount, captureSizes = 2 };
    }

    private static Mat LoadTemplate(
        string assetsRoot, string template, int width, int height, ImreadModes mode)
    {
        var resolutionRoot = Path.Combine(assetsRoot, $"{width}x{height}");
        if (!Directory.Exists(resolutionRoot))
            resolutionRoot = Path.Combine(assetsRoot, "1920x1080");
        var filePath = Path.Combine(
            resolutionRoot, template.Replace('\\', Path.DirectorySeparatorChar));
        if (!File.Exists(filePath))
            throw new FileNotFoundException($"Recognition template is missing: {filePath}", filePath);
        var mat = Cv2.ImRead(filePath, mode);
        if (mat.Empty())
            throw new InvalidDataException($"OpenCV could not decode recognition template: {filePath}");
        if (width >= 1920)
            return mat;
        using (mat)
        {
            var resized = new Mat();
            Cv2.Resize(mat, resized, new OpenCvSharp.Size(), width / 1920d, width / 1920d);
            return resized;
        }
    }
}
