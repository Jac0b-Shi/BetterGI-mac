using BetterGenshinImpact.Core.Infrastructure;
using BetterGenshinImpact.GameTask.AutoArtifactSalvage;
using BetterGenshinImpact.GameTask.AutoDomain;
using BetterGenshinImpact.GameTask.AutoFishing;
using BetterGenshinImpact.GameTask.AutoTrackPath;
using BetterGenshinImpact.GameTask.Common.BgiVision;
using BetterGenshinImpact.GameTask.Common.Job;
using BetterGenshinImpact.Verification.Framework;
using System.Globalization;

namespace BetterGenshinImpact.Core.Host.Fast.Verification;

public sealed class LocalizationResourceSuite : IVerificationSuite
{
    private static readonly CultureInfo[] Cultures =
    [
        CultureInfo.GetCultureInfo("zh-Hans"),
        CultureInfo.GetCultureInfo("zh-Hant"),
        CultureInfo.GetCultureInfo("en"),
        CultureInfo.GetCultureInfo("fr"),
    ];

    public string Name => "localization-resources";

    public Task RunAsync(
        VerificationContext context,
        CancellationToken cancellationToken)
    {
        var previousCulture = CultureInfo.CurrentCulture;
        var previousUiCulture = CultureInfo.CurrentUICulture;
        try
        {
            foreach (var culture in Cultures)
            {
                CultureInfo.CurrentCulture = culture;
                CultureInfo.CurrentUICulture = culture;
                Verify<AutoArtifactSalvageTask>(context, culture);
                Verify<AutoDomainTask>(context, culture);
                Verify<AutoFishingTask>(context, culture);
                Verify<TpTask>(context, culture);
                Verify<BvResxHelper>(context, culture);
                Verify<CheckRewardsTask>(context, culture);
                Verify<ClaimBattlePassRewardsTask>(context, culture);
                Verify<ClaimEncounterPointsRewardsTask>(context, culture);
                Verify<GoToAdventurersGuildTask>(context, culture);
                Verify<GoToCraftingBenchTask>(context, culture);
            }

            CultureInfo.CurrentCulture = Cultures[0];
            CultureInfo.CurrentUICulture = Cultures[0];
            var fallback =
                new EmbeddedResourceStringLocalizer<GoToSereniteaPotTask>()["尘歌壶"];
            context.Require(
                fallback.Value == "尘歌壶" && fallback.ResourceNotFound,
                "A task without upstream resources did not fall back to source text.");
        }
        finally
        {
            CultureInfo.CurrentCulture = previousCulture;
            CultureInfo.CurrentUICulture = previousUiCulture;
        }

        cancellationToken.ThrowIfCancellationRequested();
        return Task.CompletedTask;
    }

    private static void Verify<T>(
        VerificationContext context,
        CultureInfo culture)
    {
        var strings = new EmbeddedResourceStringLocalizer<T>()
            .GetAllStrings(includeParentCultures: false)
            .ToArray();
        context.Require(
            strings.Length > 0 && strings.All(value => !value.ResourceNotFound),
            $"{typeof(T).FullName} resources are unavailable for {culture.Name}.");
    }
}
