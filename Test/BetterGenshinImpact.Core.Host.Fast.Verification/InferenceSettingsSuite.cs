using BetterGenshinImpact.Core.Host.Runtime;
using BetterGenshinImpact.Core.Recognition.ONNX;
using BetterGenshinImpact.Verification.Framework;
using Newtonsoft.Json.Linq;

namespace BetterGenshinImpact.Core.Host.Fast.Verification;

public sealed class InferenceSettingsSuite : IVerificationSuite
{
    public string Name => "inference-settings";
    public Task RunAsync(VerificationContext context, CancellationToken cancellationToken)
    {
        var root = Path.Combine(Path.GetTempPath(), "bettergi-inference-" + Guid.NewGuid().ToString("N"));
        try
        {
            var layout = new RuntimeLayout(root);
            var catalog = new MacInferenceSettingsCatalog(layout);
            var changed = new MacInferenceSettings { CpuThreads = 1,
                PaddleOcrCpu = new() { Mode = PaddleOcrCpuMode.GameplayPriority, AllowSpinning = false } };
            var response = JObject.FromObject(catalog.Save(JObject.FromObject(changed)));
            context.Require(catalog.Active.CpuThreads == 0 && response.Value<bool>("pendingRestart"),
                "Saving inference settings leaves existing sessions on the startup snapshot");
            context.Require(response["saved"]?["paddleOcrCpu"]?["mode"]?.Value<int>() == 2,
                "Inference RPC exposes camelCase settings consumed by the Swift editor");
            context.Require(new MacInferenceSettingsCatalog(layout).Active == changed,
                "Restart reads the saved CPU and OCR thread policy");
            var rejected = false;
            try { catalog.Save(JObject.FromObject(changed with { CpuThreads = Environment.ProcessorCount + 1 })); }
            catch (ArgumentException) { rejected = true; }
            context.Require(rejected && new MacInferenceSettingsCatalog(layout).Active == changed,
                "Invalid inference settings cannot replace the last saved configuration");
            context.Require(changed.PaddleOcrCpu.Resolve(true, 1)?.IntraOpThreads == 1
                && changed.PaddleOcrCpu.Resolve(false, 1)?.IntraOpThreads == 1,
                "Gameplay OCR policy never oversubscribes a single available processor");
        }
        finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
        return Task.CompletedTask;
    }
}
