using BetterGenshinImpact.Core.Host.Fast.Verification;
using BetterGenshinImpact.Verification.Framework;

return await VerificationRunner.RunAsync(args,
[
    new TriggerSettingsSuite(),
    new LocalizationResourceSuite(),
    new SoloTaskSettingsSuite(),
    new ScriptGroupEditingSuite(),
    new PathingCatalogSuite(),
    new OneDragonPlanSuite(),
    new OneDragonCatalogSuite(),
    new OneDragonRunnerSuite(),
    new ScriptRepositorySuite(),
    new RuntimeCancellationSuite(),
    new RuntimeSettingsSuite(),
    new SchedulerStatusSuite(),
    new GameScreenshotSuite(),
    new PathRecorderSuite(),
    new NotificationRoutingSuite(),
    new KeyBindingSettingsSuite(),
    new HtmlMaskContractSuite(),
    new CaptureRingContractSuite(),
    new ScriptStartupSuite(),
    new ScriptFilePathSuite(),
    new LogParseSuite(),
    new TemplateMatchingSuite(),
    new ArtifactDownloaderSuite(),
]);
