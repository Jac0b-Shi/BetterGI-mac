using BetterGenshinImpact.Core.Host.Fast.Verification;
using BetterGenshinImpact.Verification.Framework;

return await VerificationRunner.RunAsync(args,
[
    new TriggerSettingsSuite(),
    new SoloTaskSettingsSuite(),
    new ScriptGroupEditingSuite(),
    new PathingCatalogSuite(),
    new ScriptRepositorySuite(),
    new RuntimeCancellationSuite(),
    new RuntimeSettingsSuite(),
    new SchedulerStatusSuite(),
    new GameScreenshotSuite(),
    new PathRecorderSuite(),
    new HtmlMaskContractSuite(),
    new CaptureRingContractSuite(),
]);
