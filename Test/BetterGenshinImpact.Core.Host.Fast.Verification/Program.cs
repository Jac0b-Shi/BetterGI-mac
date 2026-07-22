using BetterGenshinImpact.Core.Host.Fast.Verification;
using BetterGenshinImpact.Verification.Framework;

return await VerificationRunner.RunAsync(args,
[
    new TriggerSettingsSuite(),
    new SoloTaskSettingsSuite(),
]);
