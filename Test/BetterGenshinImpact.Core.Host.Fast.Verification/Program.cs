using BetterGenshinImpact.Core.Host.Fast.Verification;
using BetterGenshinImpact.Verification.Framework;

BetterGenshinImpact.Core.Mask.MaskWindowDrawingPlatform.Configure(new BetterGenshinImpact.Core.Mask.MaskWindowDrawingBoard());

return await VerificationRunner.RunAsync(args,
[
    // Initialise shared avatar metadata from the canonical assets before suites
    // that temporarily redirect Global.StartUpPath to minimal task fixtures.
    new AutoComboSuite(),
    new ChooseFOptionSuite(),
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
    new InferenceSettingsSuite(),
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
    new InputMaskLifecycleSuite(),
    new MusicSuite(),
    new AutoFishingSuite(),
]);
