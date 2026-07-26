using BetterGenshinImpact.Core.Host.Runtime;
using BetterGenshinImpact.Core.Script.Dependence;
using BetterGenshinImpact.Core.Script.Group;
using BetterGenshinImpact.Verification.Framework;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using Newtonsoft.Json.Linq;

namespace BetterGenshinImpact.Core.Host.Fast.Verification;

public sealed class HtmlMaskContractSuite : IVerificationSuite
{
    public string Name => "html-mask";

    public async Task RunAsync(
        VerificationContext context,
        CancellationToken cancellationToken)
    {
        ScriptHostServices.Configure(new VerificationScriptHostServices());
        var root = Path.Combine(
            Path.GetTempPath(), $"bettergi-html-mask-{Guid.NewGuid():N}");
        Directory.CreateDirectory(Path.Combine(root, "assets"));
        var calls = new List<(string Method, JObject? Parameters)>();
        using var mask = new MacHtmlMask(root, (method, parameters) =>
        {
            calls.Add((method, parameters));
            return method switch
            {
                "htmlMask.show" => JObject.FromObject(new
                {
                    windowId = parameters?.Value<string>("id") ?? "window-1"
                }),
                "htmlMask.close" => JObject.FromObject(new { closed = true }),
                "htmlMask.list" => JObject.FromObject(new { windowIds = new[] { "window-1" } }),
                "htmlMask.exists" => JObject.FromObject(new { exists = true }),
                "htmlMask.getClickThrough" => JObject.FromObject(new { enabled = true }),
                "htmlMask.request" => JObject.FromObject(new { responseJSON = """{"ready":true}""" }),
                "htmlMask.receive" => JObject.FromObject(new
                {
                    message = new { url = "/event", data = new { value = 2 } }
                }),
                "htmlMask.poll" => JObject.FromObject(new
                {
                    message = new { url = "/poll", data = true }
                }),
                "htmlMask.pollAll" => JObject.FromObject(new
                {
                    messages = new[]
                    {
                        new { url = "/one", data = 1 },
                        new { url = "/two", data = 2 },
                    }
                }),
                _ => JObject.FromObject(new { acknowledged = true }),
            };
        });

        var id = mask.Show("assets/progress-mask.html");
        mask.Send(id, "/progress", """{"progress":25}""");
        var response = await mask.Request(
            id, "/showskill", """{"show":true}""", 1_000);
        var received = await mask.Receive(id, 100);
        var polled = mask.Poll(id);
        var all = mask.PollAll(id);
        mask.SetClickThrough(id, true);
        mask.ToggleClickThrough(id);

        context.Require(
            id == "window-1" &&
            response == """{"ready":true}""" &&
            JObject.Parse(received!).Value<string>("url") == "/event" &&
            JObject.Parse(polled!).Value<string>("url") == "/poll" &&
            JArray.Parse(all).Count == 2 &&
            mask.Exists(id) &&
            mask.GetClickThrough(id) &&
            mask.GetWindowIds().SequenceEqual(["window-1"]),
            "Mac htmlMask did not preserve the upstream window and messaging contract.");

        var show = calls.Single(call => call.Method == "htmlMask.show").Parameters!;
        var send = calls.Single(call => call.Method == "htmlMask.send").Parameters!;
        context.Require(
            show.Value<string>("url") == new Uri(
                Path.Combine(root, "assets", "progress-mask.html")).AbsoluteUri &&
            show.Value<string>("workDir") == root &&
            show.Value<bool>("allowHTTP") == false &&
            send["data"]?.Value<int>("progress") == 25,
            "Mac htmlMask did not preserve the script root or structured JSON payload.");

        context.Require(
            Throws<ArgumentException>(() =>
                mask.Show("../outside.html")),
            "Mac htmlMask accepted a local file outside the script root.");

        context.Require(mask.Close(id), "Mac htmlMask did not close its window.");
        _ = mask.Show("assets/progress-mask.html", "window-2");
        _ = mask.Show("assets/progress-mask.html", "window-3");
        mask.CloseAll();
        context.Require(
            calls.Count(call => call.Method == "htmlMask.close") == 3,
            "Mac htmlMask did not close every window opened by the script instance.");
        cancellationToken.ThrowIfCancellationRequested();
        Directory.Delete(root, recursive: true);
    }

    private static bool Throws<TException>(Action action)
        where TException : Exception
    {
        try
        {
            action();
            return false;
        }
        catch (TException)
        {
            return true;
        }
    }

    private sealed class VerificationScriptHostServices : IScriptHostServices
    {
        public ILogger CreateLogger(string categoryName) => NullLogger.Instance;
        public ScriptGroupProject? CurrentProject => null;
        public TimeSpan ServerTimeZoneOffset => TimeSpan.FromHours(8);
        public bool JsNotificationEnabled => false;
        public void EmitNotification(ScriptNotificationKind kind, string message) =>
            throw new InvalidOperationException("Notification was not expected.");
    }
}
