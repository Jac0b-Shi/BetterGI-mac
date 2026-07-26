using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.Core.Host.Runtime;
using BetterGenshinImpact.Verification.Framework;
using Newtonsoft.Json.Linq;

namespace BetterGenshinImpact.Core.Host.Fast.Verification;

public sealed class LogParseSuite : IVerificationSuite
{
    public string Name => "log-parse";

    public async Task RunAsync(
        VerificationContext context,
        CancellationToken cancellationToken)
    {
        var root = Path.Combine(
            Path.GetTempPath(),
            $"bettergi-log-parse-{Guid.NewGuid():N}");
        try
        {
            var layout = new RuntimeLayout(root);
            layout.EnsureCreated();
            CopyAssets(
                FindRepositoryPath(
                    "BetterGenshinImpact",
                    "GameTask",
                    "LogParse",
                    "Assets"),
                Path.Combine(root, "GameTask", "LogParse", "Assets"));
            Global.StartUpPath = root;
            File.WriteAllLines(
                Path.Combine(
                    layout.LogPath,
                    "better-genshin-impact-20260725.log"),
                [
                    "[2026-07-25T09:00:00.123Z] [INF] Core: 17:00:00.122 info: BetterGenshinImpact.Service.ScriptService[0] 配置组 \"测试组\" 加载完成，共1个脚本",
                    "[2026-07-25T09:00:01.123Z] [INF] Core: 17:00:01.122 info: BetterGenshinImpact.Service.ScriptService[0] → 开始执行JS脚本: \"测试脚本\"",
                    "[2026-07-25T09:00:02.123Z] [INF] Core: 17:00:02.122 info: BetterGenshinImpact.Service.ScriptService[0] → 脚本执行结束: \"测试脚本\", 耗时: 1秒",
                    "[2026-07-25T09:00:03.123Z] [INF] Core: 17:00:03.122 info: BetterGenshinImpact.Service.ScriptService[0] 配置组 测试组 执行结束",
                ]);

            var coordinator = new LogParseCoordinator(layout);
            var result = await coordinator.GenerateAsync(
                "测试组",
                JObject.FromObject(new
                {
                    rangeValue = "CurrentConfig",
                    dayRangeValue = "7",
                    mergerStatsSwitch = true,
                    faultStatsSwitch = true,
                    hoeingStatsSwitch = false,
                    generateFarmingPlanData = false,
                    hoeingDelay = "2",
                    cookie = "cookie-value",
                }),
                cancellationToken);

            context.Require(
                result.LogFileCount == 1 &&
                result.ConfigGroupCount == 1 &&
                !result.HoeingStatsEnabled &&
                File.Exists(result.FilePath),
                "Log analysis did not generate one HTML result from a macOS runtime log.");
            var html = File.ReadAllText(result.FilePath);
            context.Require(
                html.Contains("测试脚本", StringComparison.Ordinal) &&
                html.Contains("2026-07-25 17:00:01", StringComparison.Ordinal),
                "Generated log analysis did not preserve the parsed task and Core-local execution time.");

            var settings = coordinator.GetSettings("测试组");
            context.Require(
                settings.RangeValue == "CurrentConfig" &&
                settings.DayRangeValue == "7" &&
                settings.MergerStatsSwitch &&
                settings.FaultStatsSwitch &&
                !settings.HoeingStatsSwitch &&
                !settings.GenerateFarmingPlanData &&
                settings.HoeingDelay == "2" &&
                settings.Cookie == "cookie-value",
                "Log-analysis settings did not persist with the selected script group.");
            context.Require(
                settings.DayRangeOptions.Select(option => option.Value)
                    .SequenceEqual(["1", "3", "7", "15", "31", "61", "92", "All"]),
                "Log-analysis day options diverged from the upstream UI semantics.");
            context.Require(
                File.Exists(coordinator.WriteCookieHelp()),
                "Log-analysis cookie help was not materialized as an HTML file.");
        }
        finally
        {
            if (Directory.Exists(root))
                Directory.Delete(root, recursive: true);
        }
    }

    private static string FindRepositoryPath(params string[] components)
    {
        for (var current = new DirectoryInfo(Directory.GetCurrentDirectory());
             current is not null;
             current = current.Parent)
        {
            var candidate = components.Aggregate(
                current.FullName,
                Path.Combine);
            if (Directory.Exists(candidate))
                return candidate;
        }
        throw new DirectoryNotFoundException(
            $"Cannot locate repository path: {Path.Combine(components)}");
    }

    private static void CopyAssets(string source, string destination)
    {
        Directory.CreateDirectory(destination);
        foreach (var file in Directory.EnumerateFiles(source))
            File.Copy(file, Path.Combine(destination, Path.GetFileName(file)));
    }
}
