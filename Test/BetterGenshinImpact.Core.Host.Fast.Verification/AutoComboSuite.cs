using BetterGenshinImpact.GameTask.AutoCombo.ComboBuild;
using BetterGenshinImpact.Verification.Framework;
using Microsoft.Extensions.Logging.Abstractions;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;

namespace BetterGenshinImpact.Core.Host.Fast.Verification;

public sealed class AutoComboSuite : IVerificationSuite
{
    public string Name => "auto-combo";

    public async Task RunAsync(VerificationContext context, CancellationToken cancellationToken)
    {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromSeconds(30));
        using var listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        var endpoint = $"http://127.0.0.1:{((IPEndPoint)listener.LocalEndpoint).Port}/v1";
        var config = new AutoComboBuildConfig { PlanningLlmEndpoint = endpoint, ModelName = "verification-model" };
        var steps = new[] { ("Sequence", "{\"name\":\"verification-combo\"}"),
            ("Jump", "{\"name\":\"verification-jump\",\"avatarName\":\"钟离\"}"),
            ("End", "{}"), ("BuildTree", "{}") };
        var requests = new List<JsonDocument>();
        var server = Task.Run(async () =>
        {
            for (var i = 0; i <= steps.Length; i++)
            {
                using var client = await listener.AcceptTcpClientAsync(timeout.Token);
                await using var stream = client.GetStream();
                requests.Add(JsonDocument.Parse(await ReadBody(stream, timeout.Token)));
                object message = i == steps.Length
                    ? new { role = "assistant", content = "Built." }
                    : new { role = "assistant", content = (string?)null, tool_calls = new[] {
                        new { id = $"call-{i}", type = "function", function = new { name = steps[i].Item1, arguments = steps[i].Item2 } } } };
                var body = JsonSerializer.SerializeToUtf8Bytes(new { id = $"response-{i}", @object = "chat.completion",
                    created = 1, model = config.ModelName, choices = new[] { new { index = 0, message,
                        finish_reason = i == steps.Length ? "stop" : "tool_calls" } } });
                await stream.WriteAsync(Encoding.ASCII.GetBytes($"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {body.Length}\r\nConnection: close\r\n\r\n"), timeout.Token);
                await stream.WriteAsync(body, timeout.Token);
            }
        }, timeout.Token);
        try
        {
            var session = await AutoComboBuildTask.BuildComboTreeAsync(["钟离"], config, NullLogger.Instance, timeout.Token);
            await server;
            context.Require(session.TeamNames.SequenceEqual(new[] { "钟离" }) &&
                CsTrees.Display.Display.AsciiTree(session.Builder.Build()).Contains("verification-jump"),
                "The real OpenAI/MEAI tool-call pipeline did not build the requested combo tree.");
            var toolNames = requests[0].RootElement.GetProperty("tools").EnumerateArray()
                .Select(t => t.GetProperty("function").GetProperty("name").GetString()).ToArray();
            context.Require(!toolNames.Contains("RunTree") && steps.All(s => toolNames.Contains(s.Item1)) &&
                requests[^1].RootElement.GetProperty("messages").EnumerateArray()
                    .Count(m => m.GetProperty("role").GetString() == "tool") == steps.Length,
                "Tool results were not returned to the real client, or RunTree was exposed to the LLM.");
        }
        finally
        {
            await timeout.CancelAsync();
            try { await server; } catch (OperationCanceledException) { }
            foreach (var request in requests) request.Dispose();
        }

        using var cancelled = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        deadline.CancelAfter(TimeSpan.FromSeconds(10));
        var build = AutoComboBuildTask.BuildComboTreeAsync(["钟离"], config, NullLogger.Instance, cancelled.Token);
        using var stalledClient = await listener.AcceptTcpClientAsync(deadline.Token);
        await ReadBody(stalledClient.GetStream(), deadline.Token);
        await cancelled.CancelAsync();
        try
        {
            await build.WaitAsync(deadline.Token);
            throw new InvalidOperationException("A cancelled LLM build unexpectedly succeeded.");
        }
        catch (OperationCanceledException) when (cancelled.IsCancellationRequested && !deadline.IsCancellationRequested)
        {
            context.Require(true, "In-flight LLM requests honour task cancellation.");
        }
    }

    private static async Task<byte[]> ReadBody(NetworkStream stream, CancellationToken ct)
    {
        var header = new StringBuilder();
        var one = new byte[1];
        while (!header.ToString().EndsWith("\r\n\r\n", StringComparison.Ordinal))
        {
            if (header.Length >= 65536 || await stream.ReadAsync(one, ct) != 1)
                throw new InvalidDataException("Incomplete HTTP request headers.");
            header.Append((char)one[0]);
        }
        var length = int.Parse(header.ToString().Split("\r\n")
            .Single(l => l.StartsWith("Content-Length:", StringComparison.OrdinalIgnoreCase)).Split(':')[1].Trim());
        var body = new byte[length];
        await stream.ReadExactlyAsync(body, ct);
        return body;
    }
}
