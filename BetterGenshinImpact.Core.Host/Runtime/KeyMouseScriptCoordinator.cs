using BetterGenshinImpact.Core.Recorder;
using BetterGenshinImpact.Core.Recorder.Model;
using BetterGenshinImpact.GameTask.Common;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json.Linq;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class KeyMouseScriptCoordinator(
    RuntimeLayout layout,
    ILogger<KeyMouseScriptCoordinator> logger,
    CancellationToken hostCancellationToken)
{
    private readonly object _lock = new();
    private readonly string _rootPath = layout.KeyMouseScriptPath;
    private CancellationTokenSource? _activeCancellation;
    private Task? _activeTask;
    private string? _activeTaskId;
    private string? _activeScriptId;
    private string _state = "idle";
    private string? _error;

    public object List()
    {
        Directory.CreateDirectory(_rootPath);
        return Directory.EnumerateFiles(_rootPath, "*.json", SearchOption.AllDirectories)
            .Select(path => new FileInfo(path))
            .OrderByDescending(file => file.CreationTime)
            .Select(file => new
            {
                id = Path.GetRelativePath(_rootPath, file.FullName).Replace('\\', '/'),
                name = file.Name,
                createdAt = file.CreationTime.ToString("yyyy-MM-dd HH:mm:ss")
            })
            .ToArray();
    }

    public object SaveRecording(JArray eventTokens, JObject infoToken)
    {
        var events = eventTokens.ToObject<List<MacroEvent>>()
            ?? throw new ArgumentException("events must be an array of macro events.");
        if (events.Count == 0)
            throw new ArgumentException("Cannot save an empty key/mouse recording.");
        ValidateEvents(events);

        var info = new KeyMouseScriptInfo
        {
            X = RequiredInt(infoToken, "x"),
            Y = RequiredInt(infoToken, "y"),
            Width = RequiredPositiveInt(infoToken, "width"),
            Height = RequiredPositiveInt(infoToken, "height"),
            RecordDpi = RequiredPositiveDouble(infoToken, "recordDpi")
        };
        var script = KeyMouseScriptBuilder.Build(events, info);
        var json = KeyMouseScriptBuilder.ToJson(script);
        Directory.CreateDirectory(_rootPath);
        var fileName = $"BetterGI_GCM_{DateTime.Now:yyyyMMddHHmmssffff}.json";
        var path = Path.Combine(_rootPath, fileName);
        var temporaryPath = $"{path}.{Guid.NewGuid():N}.tmp";
        File.WriteAllText(temporaryPath, json);
        File.Move(temporaryPath, path);
        return new
        {
            id = fileName,
            name = fileName,
            createdAt = File.GetCreationTime(path).ToString("yyyy-MM-dd HH:mm:ss"),
            eventCount = script.MacroEvents.Count
        };
    }

    public object Rename(string id, string name)
    {
        var sourcePath = ResolvePath(id);
        if (!File.Exists(sourcePath))
            throw new FileNotFoundException("Key/mouse script does not exist.", id);
        var normalizedName = name.Trim();
        if (normalizedName.EndsWith(".json", StringComparison.OrdinalIgnoreCase))
            normalizedName = normalizedName[..^5];
        if (string.IsNullOrWhiteSpace(normalizedName) ||
            normalizedName.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0)
            throw new ArgumentException("Key/mouse script name is invalid.", nameof(name));
        var destinationPath = Path.Combine(
            Path.GetDirectoryName(sourcePath)!, $"{normalizedName}.json");
        if (File.Exists(destinationPath))
            throw new IOException("A key/mouse script with that name already exists.");
        File.Move(sourcePath, destinationPath);
        return new
        {
            id = Path.GetRelativePath(_rootPath, destinationPath).Replace('\\', '/'),
            name = Path.GetFileName(destinationPath),
            createdAt = File.GetCreationTime(destinationPath).ToString("yyyy-MM-dd HH:mm:ss")
        };
    }

    public object Delete(string id)
    {
        var path = ResolvePath(id);
        if (!File.Exists(path))
            throw new FileNotFoundException("Key/mouse script does not exist.", id);
        lock (_lock)
        {
            if (_activeScriptId == id && _activeTask is { IsCompleted: false })
                throw new InvalidOperationException("Cannot delete the key/mouse script while it is playing.");
        }
        File.Delete(path);
        return new { deleted = true, id };
    }

    public object RootLocation()
    {
        Directory.CreateDirectory(_rootPath);
        return new { path = _rootPath };
    }

    public object Start(string id)
    {
        var path = ResolvePath(id);
        if (!File.Exists(path))
            throw new FileNotFoundException("Key/mouse script does not exist.", id);

        lock (_lock)
        {
            if (_activeTask is { IsCompleted: false })
                throw new InvalidOperationException("A key/mouse script is already playing.");
            _activeCancellation?.Dispose();
            _activeCancellation = CancellationTokenSource.CreateLinkedTokenSource(hostCancellationToken);
            _activeTaskId = Guid.NewGuid().ToString("N");
            _activeScriptId = id;
            _state = "running";
            _error = null;
            var taskId = _activeTaskId;
            var cancellationToken = _activeCancellation.Token;
            _activeTask = Task.Run(
                () => RunAsync(taskId, id, path, cancellationToken),
                CancellationToken.None);
            return StatusLocked();
        }
    }

    public async Task<object> StopAsync()
    {
        Task? activeTask;
        lock (_lock)
        {
            if (_activeTask is not { IsCompleted: false })
                return StatusLocked();
            _state = "stopping";
            _activeCancellation?.Cancel();
            activeTask = _activeTask;
        }
        try { await activeTask; }
        catch (OperationCanceledException) { }
        return Status();
    }

    public object Status()
    {
        lock (_lock)
            return StatusLocked();
    }

    private async Task RunAsync(
        string taskId,
        string scriptId,
        string path,
        CancellationToken cancellationToken)
    {
        try
        {
            var json = await File.ReadAllTextAsync(path, cancellationToken);
            logger.LogInformation("重放开始：{Name}", Path.GetFileName(path));
            await KeyMouseMacroPlayer.PlayMacro(json, cancellationToken);
            Complete(taskId, "completed", null);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            Complete(taskId, "cancelled", null);
        }
        catch (Exception exception)
        {
            logger.LogError(exception, "重放脚本时发生异常：{Name}", scriptId);
            Complete(taskId, "failed", exception.Message);
        }
        finally
        {
            try { TaskControl.ReleaseAllKey(); }
            catch (Exception exception)
            {
                logger.LogWarning(exception, "键鼠脚本结束后释放输入失败");
            }
            logger.LogInformation("重放结束：{Name}", Path.GetFileName(path));
        }
    }

    private void Complete(string taskId, string state, string? error)
    {
        lock (_lock)
        {
            if (_activeTaskId != taskId)
                return;
            _state = state;
            _error = error;
        }
    }

    private object StatusLocked() => new
    {
        taskId = _activeTaskId,
        scriptId = _activeScriptId,
        state = _state,
        error = _error
    };

    private string ResolvePath(string id)
    {
        if (string.IsNullOrWhiteSpace(id) || Path.IsPathRooted(id))
            throw new ArgumentException("Key/mouse script id is invalid.", nameof(id));
        var root = Path.GetFullPath(_rootPath);
        var candidate = Path.GetFullPath(Path.Combine(root, id.Replace('/', Path.DirectorySeparatorChar)));
        if (!candidate.StartsWith(root + Path.DirectorySeparatorChar, StringComparison.Ordinal) ||
            !string.Equals(Path.GetExtension(candidate), ".json", StringComparison.OrdinalIgnoreCase))
            throw new ArgumentException("Key/mouse script id escapes the script root.", nameof(id));
        return candidate;
    }

    private static void ValidateEvents(IEnumerable<MacroEvent> events)
    {
        foreach (var macroEvent in events)
        {
            if (!Enum.IsDefined(macroEvent.Type))
                throw new ArgumentException($"Unknown macro event type: {macroEvent.Type}.");
            if (!double.IsFinite(macroEvent.Time))
                throw new ArgumentException("Macro event time must be finite.");
            if (macroEvent.Type is MacroEventType.KeyDown or MacroEventType.KeyUp &&
                macroEvent.KeyCode is not > 0)
                throw new ArgumentException("Keyboard macro events require a positive keyCode.");
            if (macroEvent.Type is MacroEventType.MouseDown or MacroEventType.MouseUp &&
                macroEvent.MouseButton is not ("Left" or "Right" or "Middle" or "XButton1" or "XButton2"))
                throw new ArgumentException(
                    "Mouse button macro events require Left, Right, Middle, XButton1 or XButton2.");
        }
    }

    private static int RequiredInt(JObject value, string name) =>
        value.Value<int?>(name) ?? throw new ArgumentException($"{name} is required.");

    private static int RequiredPositiveInt(JObject value, string name)
    {
        var result = RequiredInt(value, name);
        return result > 0 ? result : throw new ArgumentException($"{name} must be positive.");
    }

    private static double RequiredPositiveDouble(JObject value, string name)
    {
        var result = value.Value<double?>(name)
            ?? throw new ArgumentException($"{name} is required.");
        return double.IsFinite(result) && result > 0
            ? result
            : throw new ArgumentException($"{name} must be finite and positive.");
    }
}
