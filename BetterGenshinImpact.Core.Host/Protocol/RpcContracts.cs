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
    [property: JsonProperty("hideOnRepeat")] bool HideOnRepeat,
    [property: JsonProperty("projects")] IReadOnlyList<ScriptGroupProjectSummary> Projects);

public sealed record ScriptGroupProjectSummary(
    [property: JsonProperty("index")] int Index,
    [property: JsonProperty("name")] string Name,
    [property: JsonProperty("type")] string Type,
    [property: JsonProperty("status")] string Status,
    [property: JsonProperty("schedule")] string Schedule,
    [property: JsonProperty("runNum")] int RunNum,
    [property: JsonProperty("folderName")] string FolderName,
    [property: JsonProperty("hasCustomSettings")] bool HasCustomSettings,
    [property: JsonProperty("nextFlag")] bool NextFlag);

public sealed record ScriptGroupProjectCommonSettings(
    [property: JsonProperty("index")] int Index,
    [property: JsonProperty("status")] string Status,
    [property: JsonProperty("isJavascript")] bool IsJavascript,
    [property: JsonProperty("allowJsNotification")] bool? AllowJsNotification,
    [property: JsonProperty("allowJsHttp")] bool AllowJsHttp,
    [property: JsonProperty("httpAllowedUrls")] IReadOnlyList<string> HttpAllowedUrls);

public sealed record ScriptGroupProjectCustomSettings(
    [property: JsonProperty("index")] int Index,
    [property: JsonProperty("schema")] object Schema,
    [property: JsonProperty("values")] JObject Values);

public sealed record ScriptGroupAddCandidate(
    [property: JsonProperty("id")] string Id,
    [property: JsonProperty("name")] string Name,
    [property: JsonProperty("folderName")] string FolderName,
    [property: JsonProperty("type")] string Type);

public sealed record PathingCatalogEntry(
    [property: JsonProperty("id")] string Id,
    [property: JsonProperty("parentId")] string? ParentId,
    [property: JsonProperty("name")] string Name,
    [property: JsonProperty("isDirectory")] bool IsDirectory);

public sealed record PathingTaskDetail(
    [property: JsonProperty("id")] string Id,
    [property: JsonProperty("name")] string Name,
    [property: JsonProperty("description")] string? Description,
    [property: JsonProperty("author")] string? Author,
    [property: JsonProperty("version")] string? Version,
    [property: JsonProperty("bgiVersion")] string? BgiVersion,
    [property: JsonProperty("type")] string Type,
    [property: JsonProperty("mapName")] string MapName,
    [property: JsonProperty("waypointCount")] int WaypointCount,
    [property: JsonProperty("tags")] IReadOnlyList<string> Tags,
    [property: JsonProperty("readme")] string? Readme);

public sealed record ScriptProjectDocument(
    [property: JsonProperty("folderName")] string FolderName,
    [property: JsonProperty("manifest")] object Manifest,
    [property: JsonProperty("settings")] object Settings);

public sealed record ScriptProjectSummary(
    [property: JsonProperty("folderName")] string FolderName,
    [property: JsonProperty("name")] string Name,
    [property: JsonProperty("version")] string Version);

public sealed record ScriptRepositoryState(
    [property: JsonProperty("available")] bool Available,
    [property: JsonProperty("repositoryPath")] string RepositoryPath,
    [property: JsonProperty("indexPath")] string? IndexPath,
    [property: JsonProperty("webIndexPath")] string? WebIndexPath,
    [property: JsonProperty("lastUpdated")] DateTime? LastUpdated,
    [property: JsonProperty("subscribedPaths")] IReadOnlyList<string> SubscribedPaths);

public sealed record ScriptRepositoryUpdateResult(
    [property: JsonProperty("status")] string Status,
    [property: JsonProperty("channel")] string Channel,
    [property: JsonProperty("repositoryPath")] string RepositoryPath,
    [property: JsonProperty("indexPath")] string IndexPath);

public sealed record ScriptRepositoryBatchUpdateResult(
    [property: JsonProperty("attemptedCount")] int AttemptedCount,
    [property: JsonProperty("successCount")] int SuccessCount,
    [property: JsonProperty("failureCount")] int FailureCount,
    [property: JsonProperty("failedPaths")] IReadOnlyList<string> FailedPaths,
    [property: JsonProperty("subscribedPaths")] IReadOnlyList<string> SubscribedPaths);

public sealed record ScriptRepositoryImportResult(
    [property: JsonProperty("installedCount")] int InstalledCount,
    [property: JsonProperty("subscribedPaths")] IReadOnlyList<string> SubscribedPaths);

public sealed record ScriptRepositoryInstallResult(
    [property: JsonProperty("path")] string Path,
    [property: JsonProperty("destinationPath")] string DestinationPath,
    [property: JsonProperty("subscribedPaths")] IReadOnlyList<string> SubscribedPaths);
