using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace BetterGenshinImpact.Core.Host.Protocol;

public sealed record RpcRequest(
    [property: JsonProperty("id")] string Id,
    [property: JsonProperty("method")] string Method,
    [property: JsonProperty("params")] JObject? Params,
    [property: JsonProperty("sessionToken")] string SessionToken);

public sealed record RpcResponse(
    [property: JsonProperty("id")] string Id,
    [property: JsonProperty("result", NullValueHandling = NullValueHandling.Ignore)] object? Result,
    [property: JsonProperty("error", NullValueHandling = NullValueHandling.Ignore)] RpcError? Error)
{
    public static RpcResponse Success(string id, object? result) => new(id, result, null);
    public static RpcResponse Failure(string id, string code, string message, object? data = null) =>
        new(id, null, new RpcError(code, message, data));
}

public sealed record RpcError(
    [property: JsonProperty("code")] string Code,
    [property: JsonProperty("message")] string Message,
    [property: JsonProperty("data", NullValueHandling = NullValueHandling.Ignore)] object? Data);

public sealed record ScriptGroupDocument(
    [property: JsonProperty("name")] string Name,
    [property: JsonProperty("path")] string Path,
    [property: JsonProperty("document")] JObject Document);

public sealed record ScriptGroupSummary(
    [property: JsonProperty("name")] string Name,
    [property: JsonProperty("path")] string Path,
    [property: JsonProperty("index")] int Index,
    [property: JsonProperty("projects")] IReadOnlyList<ScriptGroupProjectSummary> Projects);

public sealed record ScriptGroupProjectSummary(
    [property: JsonProperty("index")] int Index,
    [property: JsonProperty("name")] string Name,
    [property: JsonProperty("type")] string Type,
    [property: JsonProperty("status")] string Status,
    [property: JsonProperty("schedule")] string Schedule,
    [property: JsonProperty("runNum")] int RunNum);

public sealed record ScriptProjectDocument(
    [property: JsonProperty("folderName")] string FolderName,
    [property: JsonProperty("manifest")] object Manifest,
    [property: JsonProperty("settings")] object Settings);
