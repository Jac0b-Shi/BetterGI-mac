using BetterGenshinImpact.Core.Host.Transport;
using BetterGenshinImpact.Core.Script.Dependence;
using BetterGenshinImpact.Core.Script.Utils;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace BetterGenshinImpact.Core.Host.Runtime;

internal sealed class MacHtmlMask : IDisposable
{
    private readonly string _workDir;
    private readonly Func<string, JObject?, JToken?> _invoke;
    private readonly HashSet<string> _openedWindowIds = new(StringComparer.Ordinal);
    private bool _disposed;

    public MacHtmlMask(
        string workDir,
        PlatformCallbackChannel callbacks,
        string sessionToken,
        CancellationToken cancellationToken)
        : this(
            workDir,
            (method, parameters) => callbacks.InvokeAsync(
                    method, parameters, sessionToken, cancellationToken)
                .GetAwaiter()
                .GetResult())
    {
    }

    internal MacHtmlMask(
        string workDir,
        Func<string, JObject?, JToken?> invoke)
    {
        _workDir = Path.GetFullPath(workDir);
        _invoke = invoke;
    }

    public string Show(string url, string? id = null)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        if (string.IsNullOrWhiteSpace(url))
            throw new ArgumentException("URL不能为空", nameof(url));

        var pageUrl = ResolveUrl(url);
        var project = ScriptHostServices.CurrentProject;
        var result = RequireObject("htmlMask.show", JObject.FromObject(new
        {
            url = pageUrl,
            id,
            workDir = _workDir,
            allowHTTP = project?.AllowJsHTTP == true,
            allowedUrls = project?.Project?.Manifest.HttpAllowedUrls ?? [],
        }));
        var windowId = result.Value<string>("windowId");
        if (string.IsNullOrWhiteSpace(windowId))
            throw new InvalidDataException("htmlMask.show did not return a windowId.");
        lock (_openedWindowIds)
            _openedWindowIds.Add(windowId);
        return windowId;
    }

    public bool Close(string id)
    {
        var result = RequireObject(
            "htmlMask.close", JObject.FromObject(new { windowId = RequiredId(id) }));
        lock (_openedWindowIds)
            _openedWindowIds.Remove(id);
        return result.Value<bool>("closed");
    }

    public void CloseAll()
    {
        string[] windowIds;
        lock (_openedWindowIds)
        {
            windowIds = [.. _openedWindowIds];
            _openedWindowIds.Clear();
        }
        foreach (var windowId in windowIds)
        {
            try
            {
                _ = RequireObject(
                    "htmlMask.close", JObject.FromObject(new { windowId }));
            }
            catch (OperationCanceledException) when (_disposed)
            {
                return;
            }
        }
    }

    public string[] GetWindowIds()
    {
        var result = RequireObject("htmlMask.list", null);
        return result["windowIds"]?.ToObject<string[]>() ?? [];
    }

    public bool Exists(string id)
    {
        var result = RequireObject(
            "htmlMask.exists", JObject.FromObject(new { windowId = RequiredId(id) }));
        return result.Value<bool>("exists");
    }

    public void SetClickThrough(string windowId, bool enabled)
    {
        RequireAcknowledgement("htmlMask.setClickThrough", JObject.FromObject(new
        {
            windowId = RequiredId(windowId),
            enabled,
        }));
    }

    public bool GetClickThrough(string windowId)
    {
        var result = RequireObject(
            "htmlMask.getClickThrough",
            JObject.FromObject(new { windowId = RequiredId(windowId) }));
        return result.Value<bool>("enabled");
    }

    public void ToggleClickThrough(string windowId)
    {
        RequireAcknowledgement(
            "htmlMask.toggleClickThrough",
            JObject.FromObject(new { windowId = RequiredId(windowId) }));
    }

    public void Send(string windowId, string url, string jsonData)
    {
        RequireAcknowledgement("htmlMask.send", MessageParameters(
            windowId, url, jsonData, requestId: null));
    }

    public void Respond(string windowId, string requestId, string jsonData)
    {
        if (string.IsNullOrWhiteSpace(requestId))
            throw new ArgumentException("requestId cannot be empty", nameof(requestId));
        RequireAcknowledgement("htmlMask.respond", MessageParameters(
            windowId, "/__response__", jsonData, requestId));
    }

    public async Task<string?> Request(
        string windowId,
        string url,
        string jsonData,
        int timeoutMs = 0)
    {
        if (timeoutMs < 0)
            throw new ArgumentOutOfRangeException(nameof(timeoutMs));
        var parameters = MessageParameters(windowId, url, jsonData, requestId: null);
        parameters["timeoutMs"] = timeoutMs;
        var result = await Task.Run(() => RequireObject("htmlMask.request", parameters));
        return result.Value<string>("responseJSON");
    }

    public async Task<string?> Receive(string windowId, int timeoutMs = 0)
    {
        if (timeoutMs < 0)
            throw new ArgumentOutOfRangeException(nameof(timeoutMs));
        var result = await Task.Run(() => RequireObject(
            "htmlMask.receive",
            JObject.FromObject(new
            {
                windowId = RequiredId(windowId),
                timeoutMs,
            })));
        return SerializeOptional(result["message"]);
    }

    public string? Poll(string windowId)
    {
        var result = RequireObject(
            "htmlMask.poll",
            JObject.FromObject(new { windowId = RequiredId(windowId) }));
        return SerializeOptional(result["message"]);
    }

    public string PollAll(string windowId)
    {
        var result = RequireObject(
            "htmlMask.pollAll",
            JObject.FromObject(new { windowId = RequiredId(windowId) }));
        return (result["messages"] ?? new JArray()).ToString(Formatting.None);
    }

    public void Dispose()
    {
        if (_disposed)
            return;
        CloseAll();
        _disposed = true;
    }

    private string ResolveUrl(string url)
    {
        if (Uri.TryCreate(url, UriKind.Absolute, out var absolute))
        {
            if (absolute.Scheme is "http" or "https")
                return absolute.AbsoluteUri;
            if (absolute.IsFile)
            {
                var fullPath = Path.GetFullPath(absolute.LocalPath);
                EnsureUnderWorkDir(fullPath);
                return new Uri(fullPath).AbsoluteUri;
            }
            throw new ArgumentException("HTML遮罩仅支持脚本目录文件或 HTTP(S) URL。", nameof(url));
        }

        var path = ScriptUtils.NormalizePath(_workDir, url);
        EnsureUnderWorkDir(path);
        return new Uri(path).AbsoluteUri;
    }

    private void EnsureUnderWorkDir(string path)
    {
        var fullPath = Path.GetFullPath(path);
        if (!fullPath.StartsWith(
                _workDir + Path.DirectorySeparatorChar,
                StringComparison.Ordinal) &&
            !string.Equals(fullPath, _workDir, StringComparison.Ordinal))
        {
            throw new UnauthorizedAccessException("HTML遮罩文件必须位于当前脚本目录。");
        }
    }

    private static JObject MessageParameters(
        string windowId,
        string url,
        string? jsonData,
        string? requestId)
    {
        if (string.IsNullOrWhiteSpace(url))
            throw new ArgumentException("消息 URL 不能为空。", nameof(url));
        return JObject.FromObject(new
        {
            windowId = RequiredId(windowId),
            url,
            data = ParseData(jsonData),
            requestId,
        });
    }

    private static JToken? ParseData(string? json)
    {
        if (string.IsNullOrWhiteSpace(json))
            return null;
        try
        {
            return JToken.Parse(json);
        }
        catch (JsonReaderException)
        {
            return new JValue(json);
        }
    }

    private static string RequiredId(string id)
    {
        if (string.IsNullOrWhiteSpace(id))
            throw new ArgumentException("HTML遮罩窗口 ID 不能为空。", nameof(id));
        return id;
    }

    private JObject RequireObject(string method, JObject? parameters)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        return _invoke(method, parameters) as JObject
            ?? throw new InvalidDataException($"{method} did not return an object.");
    }

    private void RequireAcknowledgement(string method, JObject parameters)
    {
        var result = RequireObject(method, parameters);
        if (result.Value<bool?>("acknowledged") != true)
            throw new InvalidDataException($"{method} was not acknowledged.");
    }

    private static string? SerializeOptional(JToken? token) =>
        token is null || token.Type is JTokenType.Null or JTokenType.Undefined
            ? null
            : token.ToString(Formatting.None);
}
