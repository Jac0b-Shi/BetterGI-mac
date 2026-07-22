using BetterGenshinImpact.Core.Host.Protocol;
using BetterGenshinImpact.Core.Host.Runtime;
using BetterGenshinImpact.Core.Host.Transport;
using Newtonsoft.Json.Linq;
using System.Net.Sockets;
using System.Runtime.Versioning;
using System.Security.Cryptography;
using BetterGenshinImpact.GameTask;

namespace BetterGenshinImpact.Core.Host;

[SupportedOSPlatform("macos")]
public sealed class CoreRpcServer(
    string socketPath,
    string sessionToken,
    RuntimeLayout layout,
    NativeDependencyStatus nativeDependencies)
{
    public const int ProtocolVersion = 1;
    private readonly ScriptGroupCatalog _catalog = new(layout);
    private readonly ScriptProjectCatalog _scriptProjectCatalog = new(layout);
    private readonly SoloTaskSettingsCatalog _soloTaskSettings = new(layout);
    private readonly TriggerSettingsCatalog _triggerSettings = new(layout);
    private readonly PlatformCallbackChannel _platformCallbacks = new();
    private SchedulerCoordinator? _scheduler;
    private readonly CancellationTokenSource _shutdown = new();
    private readonly object _connectionsLock = new();
    private readonly HashSet<Task> _connections = [];
    private MacScriptHostServices? _scriptHostServices;
    private MacScriptServicePlatform? _scriptServicePlatform;
    private MacPathExecutorPlatform? _pathExecutorPlatform;
    private Func<RuntimeArtifactStatus>? _runtimeArtifactInitializer;
    private RuntimeArtifactStatus? _runtimeArtifactStatus;
    private Action? _platformAssetInitializer;
    private MacTriggerDispatcher? _triggerDispatcher;
    private SoloTaskCoordinator? _soloTasks;
    private int _platformAssetsInitialized;
    private readonly SemaphoreSlim _runtimeMutationLock = new(1, 1);
    public PlatformCallbackChannel PlatformCallbacks => _platformCallbacks;
    public SoloTaskSettingsCatalog SoloTaskSettings => _soloTaskSettings;
    public TriggerSettingsCatalog TriggerSettings => _triggerSettings;

    private SchedulerCoordinator Scheduler => _scheduler ??= new SchedulerCoordinator(
        layout, _platformCallbacks, sessionToken, _shutdown.Token);
    private SoloTaskCoordinator SoloTasks => _soloTasks ?? throw new CapabilityUnavailableException(
        "Solo task coordinator is unavailable until Core composition completes.");

    public void AttachScriptHostServices(MacScriptHostServices services)
    {
        ArgumentNullException.ThrowIfNull(services);
        if (Interlocked.CompareExchange(ref _scriptHostServices, services, null) is not null)
            throw new InvalidOperationException("Script host services have already been attached.");
    }

    public void AttachScriptServicePlatform(MacScriptServicePlatform platform)
    {
        ArgumentNullException.ThrowIfNull(platform);
        if (Interlocked.CompareExchange(ref _scriptServicePlatform, platform, null) is not null)
            throw new InvalidOperationException("Script service platform has already been attached.");
    }

    public void AttachPlatformAssetInitializer(Action initializer)
    {
        ArgumentNullException.ThrowIfNull(initializer);
        if (Interlocked.CompareExchange(ref _platformAssetInitializer, initializer, null) is not null)
            throw new InvalidOperationException("Platform asset initializer has already been attached.");
    }

    public void AttachTriggerDispatcher(MacTriggerDispatcher dispatcher)
    {
        ArgumentNullException.ThrowIfNull(dispatcher);
        if (Interlocked.CompareExchange(ref _triggerDispatcher, dispatcher, null) is not null)
            throw new InvalidOperationException("Trigger dispatcher has already been attached.");
    }

    public void AttachSoloTaskCoordinator(SoloTaskCoordinator coordinator)
    {
        ArgumentNullException.ThrowIfNull(coordinator);
        if (Interlocked.CompareExchange(ref _soloTasks, coordinator, null) is not null)
            throw new InvalidOperationException("Solo task coordinator has already been attached.");
    }

    public void AttachRuntimeArtifactInitializer(Func<RuntimeArtifactStatus> initializer)
    {
        ArgumentNullException.ThrowIfNull(initializer);
        if (Interlocked.CompareExchange(ref _runtimeArtifactInitializer, initializer, null) is not null)
            throw new InvalidOperationException("Runtime artifact initializer has already been attached.");
    }

    public void AttachPathExecutorPlatform(MacPathExecutorPlatform platform)
    {
        ArgumentNullException.ThrowIfNull(platform);
        if (Interlocked.CompareExchange(ref _pathExecutorPlatform, platform, null) is not null)
            throw new InvalidOperationException("PathExecutor platform has already been attached.");
    }

    public async Task RunAsync(CancellationToken cancellationToken)
    {
        layout.EnsureCreated();
        if (File.Exists(socketPath)) File.Delete(socketPath);
        using var listener = new Socket(AddressFamily.Unix, SocketType.Stream, ProtocolType.Unspecified);
        listener.Bind(new UnixDomainSocketEndPoint(socketPath));
        File.SetUnixFileMode(socketPath, UnixFileMode.UserRead | UnixFileMode.UserWrite);
        listener.Listen(8);
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, _shutdown.Token);
        try
        {
            while (!linked.IsCancellationRequested)
            {
                var socket = await listener.AcceptAsync(linked.Token);
                var task = HandleConnectionAsync(socket, linked.Token);
                lock (_connectionsLock) _connections.Add(task);
                _ = task.ContinueWith(completed =>
                {
                    lock (_connectionsLock) _connections.Remove(completed);
                }, CancellationToken.None, TaskContinuationOptions.ExecuteSynchronously, TaskScheduler.Default);
            }
        }
        catch (OperationCanceledException) when (linked.IsCancellationRequested) { }
        finally
        {
            if (File.Exists(socketPath)) File.Delete(socketPath);
            Task[] connections;
            lock (_connectionsLock) connections = [.. _connections];
            try { await Task.WhenAll(connections); } catch (OperationCanceledException) { }
        }
    }

    private async Task HandleConnectionAsync(Socket socket, CancellationToken cancellationToken)
    {
        await using var connection = new FramedJsonConnection(socket);
        while (!cancellationToken.IsCancellationRequested)
        {
            RpcRequest? request;
            try { request = await connection.ReadRequestAsync(cancellationToken); }
            catch (Exception ex)
            {
                await connection.WriteResponseAsync(RpcResponse.Failure("unknown", "InvalidRequest", ex.Message), cancellationToken);
                return;
            }
            if (request is null) return;
            if (request.Method == "platform.attach")
            {
                if (!TokenIsValid(request.SessionToken))
                {
                    await connection.WriteResponseAsync(RpcResponse.Failure(request.Id, "Unauthorized", "Invalid session token."), cancellationToken);
                    return;
                }
                await connection.WriteResponseAsync(RpcResponse.Success(request.Id, new { attached = true }), cancellationToken);
                try { await _platformCallbacks.AttachAsync(connection, cancellationToken); }
                finally { _platformCallbacks.Detach(connection); }
                return;
            }
            var response = await DispatchAsync(request);
            await connection.WriteResponseAsync(response, cancellationToken);
        }
    }

    private async Task<RpcResponse> DispatchAsync(RpcRequest request)
    {
        if (!TokenIsValid(request.SessionToken))
            return RpcResponse.Failure(request.Id, "Unauthorized", "Invalid session token.");

        try
        {
            if (request.Method == "runtime.stop")
            {
                return RpcResponse.Success(
                    request.Id, await StopRuntimeAsync(_shutdown.Token));
            }
            if (request.Method == "runtime.start")
            {
                return RpcResponse.Success(
                    request.Id, await StartRuntimeAsync(_shutdown.Token));
            }
            if (request.Method == "runtime.refreshGeometry")
            {
                return RpcResponse.Success(
                    request.Id, await RefreshRuntimeGeometryAsync(_shutdown.Token));
            }
            object? result = request.Method switch
            {
                "core.handshake" => Handshake(),
                "core.initialize" => Initialize(request.Params),
                "catalog.listScriptGroups" => _catalog.List(),
                "catalog.getScriptGroup" => _catalog.Get(RequiredString(request.Params, "name")),
                "catalog.saveScriptGroup" => _catalog.Save(
                    RequiredString(request.Params, "name"),
                    request.Params?["document"] as JObject ?? throw new ArgumentException("document is required.")),
                "catalog.setScriptGroupProjectEnabled" => _catalog.SetProjectEnabled(
                    RequiredString(request.Params, "name"),
                    request.Params?.Value<int?>("projectIndex")
                        ?? throw new ArgumentException("projectIndex is required."),
                    request.Params?.Value<bool?>("enabled")
                        ?? throw new ArgumentException("enabled is required.")),
                "catalog.listScriptProjects" => _scriptProjectCatalog.List(),
                "catalog.getScriptProject" => _scriptProjectCatalog.Get(RequiredString(request.Params, "folderName")),
                "trigger.list" => ListTriggers(),
                "trigger.setEnabled" => SetTriggerEnabled(
                    RequiredString(request.Params, "name"),
                    request.Params?.Value<bool?>("enabled")
                        ?? throw new ArgumentException("enabled is required.")),
                "trigger.settings.get" => _triggerSettings.Get(
                    RequiredString(request.Params, "name")),
                "trigger.settings.save" => _triggerSettings.Save(
                    RequiredString(request.Params, "name"),
                    request.Params?["settings"] as JObject
                    ?? throw new ArgumentException("settings is required.")),
                "solo.list" => SoloTasks.List(),
                "solo.start" => SoloTasks.Start(
                    RequiredString(request.Params, "name"),
                    request.Params?["inputText"]?.Value<string>()),
                "solo.stop" => SoloTasks.Stop(RequiredString(request.Params, "taskId")),
                "solo.status" => SoloTasks.Status(),
                "solo.settings.get" => _soloTaskSettings.Get(RequiredString(request.Params, "name")),
                "solo.settings.save" => _soloTaskSettings.Save(
                    RequiredString(request.Params, "name"),
                    request.Params?["settings"] as JObject
                    ?? throw new ArgumentException("settings is required.")),
                "runtime.status" => RuntimeStatus(),
                "scheduler.run" => Scheduler.Run(RequiredString(request.Params, "groupName")),
                "scheduler.pause" => Scheduler.Pause(RequiredString(request.Params, "taskId")),
                "scheduler.resume" => Scheduler.Resume(RequiredString(request.Params, "taskId")),
                "scheduler.stop" => Scheduler.Stop(RequiredString(request.Params, "taskId")),
                "core.shutdown" => Shutdown(),
                _ => throw new MissingMethodException($"Unknown RPC method: {request.Method}")
            };
            return RpcResponse.Success(request.Id, result);
        }
        catch (CapabilityUnavailableException ex)
        {
            return RpcResponse.Failure(request.Id, "CapabilityUnavailable", ex.Message);
        }
        catch (Exception ex)
        {
            return RpcResponse.Failure(request.Id, ex.GetType().Name, ex.Message);
        }
    }

    private bool TokenIsValid(string token)
    {
        var providedToken = System.Text.Encoding.UTF8.GetBytes(token);
        var expectedToken = System.Text.Encoding.UTF8.GetBytes(sessionToken);
        return providedToken.Length == expectedToken.Length &&
               CryptographicOperations.FixedTimeEquals(providedToken, expectedToken);
    }

    private object Handshake()
    {
        return new
        {
            protocolVersion = ProtocolVersion,
            runtimeVersion = nativeDependencies.RuntimeVersion,
            architecture = nativeDependencies.Architecture,
            openCvVersion = nativeDependencies.OpenCvVersion,
            clearScriptReady = nativeDependencies.ClearScriptReady,
            capabilities = new[]
            {
                "catalog.script-groups",
                "catalog.script-projects",
                "runtime-layout",
                "runtime-artifacts.source-lock",
                "opencv",
                "clearscript-v8",
                "trigger-control",
                "runtime-control",
                "runtime.geometry-refresh",
                "scheduler.run"
            }
        };
    }

    private object Initialize(JObject? parameters)
    {
        var requestedRoot = parameters?.Value<string>("runtimeRoot");
        if (!string.IsNullOrWhiteSpace(requestedRoot) && Path.GetFullPath(requestedRoot) != layout.RootPath)
            throw new InvalidOperationException("Runtime root cannot change after process startup.");
        layout.EnsureCreated();
        if (_runtimeArtifactInitializer is not null && _runtimeArtifactStatus is null)
            _runtimeArtifactStatus = _runtimeArtifactInitializer();
        if (_platformCallbacks.IsAttached && _platformAssetInitializer is not null &&
            Interlocked.CompareExchange(ref _platformAssetsInitialized, 1, 0) == 0)
        {
            try { _platformAssetInitializer(); }
            catch
            {
                Volatile.Write(ref _platformAssetsInitialized, 0);
                throw;
            }
        }
        if (parameters?.Value<double?>("serverTimeZoneOffsetHours") is { } offsetHours)
            _scriptHostServices?.SetServerTimeZoneOffset(TimeSpan.FromHours(offsetHours));
        if (parameters?.Value<bool?>("jsNotificationEnabled") is { } notificationsEnabled)
            _scriptHostServices?.SetJsNotificationEnabled(notificationsEnabled);
        if (parameters?.Value<string>("mapMatchingMethod") is { Length: > 0 } mapMatchingMethod)
            _scriptServicePlatform?.SetMapMatchingMethod(mapMatchingMethod);
        if (parameters?.Value<string>("autoFetchDispatchAdventurersGuildCountry") is { Length: > 0 } country)
            _pathExecutorPlatform?.SetAutoFetchDispatchAdventurersGuildCountry(country);
        return new
        {
            runtimeRoot = layout.RootPath,
            scriptGroupPath = layout.ScriptGroupPath,
            platformCallbackAttached = _platformCallbacks.IsAttached,
            scriptHostServicesAttached = _scriptHostServices is not null,
            scriptServicePlatformAttached = _scriptServicePlatform is not null,
            platformAssetsInitialized = Volatile.Read(ref _platformAssetsInitialized) == 1,
            runtimeArtifactsReady = _runtimeArtifactInitializer is null || _runtimeArtifactStatus is not null,
            runtimeArtifactsExtracted = _runtimeArtifactStatus?.Extracted ?? 0,
            runtimeArtifactsVerified = _runtimeArtifactStatus?.VerifiedExisting ?? 0,
            mapMatchingMethod = _scriptServicePlatform?.MapMatchingMethod,
            autoFetchDispatchAdventurersGuildCountry =
                _pathExecutorPlatform?.AutoFetchDispatchAdventurersGuildCountry
        };
    }

    private object Shutdown()
    {
        _shutdown.Cancel();
        return new { stopping = true };
    }

    private async Task<object> StartRuntimeAsync(CancellationToken cancellationToken)
    {
        await _runtimeMutationLock.WaitAsync(cancellationToken);
        try
        {
            if (Volatile.Read(ref _platformAssetsInitialized) != 1)
                throw new CapabilityUnavailableException(
                    "The macOS trigger runtime is unavailable until core.initialize completes with the platform attached.");
            var dispatcher = RequiredTriggerDispatcher();
            if (!dispatcher.IsRunning)
                dispatcher.Start();
            return RuntimeStatus();
        }
        finally
        {
            _runtimeMutationLock.Release();
        }
    }

    private async Task<object> StopRuntimeAsync(CancellationToken cancellationToken)
    {
        await _runtimeMutationLock.WaitAsync(cancellationToken);
        try
        {
            await RequiredTriggerDispatcher().StopAsync();
            return RuntimeStatus();
        }
        finally
        {
            _runtimeMutationLock.Release();
        }
    }

    private object RuntimeStatus() => new { running = RequiredTriggerDispatcher().IsRunning };

    private async Task<object> RefreshRuntimeGeometryAsync(CancellationToken cancellationToken)
    {
        await _runtimeMutationLock.WaitAsync(cancellationToken);
        try
        {
            if (Volatile.Read(ref _platformAssetsInitialized) != 1 || _platformAssetInitializer is null)
                throw new CapabilityUnavailableException(
                    "Runtime geometry cannot refresh before platform assets are initialized.");
            var dispatcher = RequiredTriggerDispatcher();
            var restart = dispatcher.IsRunning;
            if (restart)
                await dispatcher.StopAsync();

            var enabledStates = GameTaskManager.TriggerDictionary?
                .ToDictionary(pair => pair.Key, pair => pair.Value.IsEnabled, StringComparer.Ordinal)
                ?? new Dictionary<string, bool>(StringComparer.Ordinal);
            _platformAssetInitializer();
            if (GameTaskManager.TriggerDictionary is { } triggers)
            {
                foreach (var (name, enabled) in enabledStates)
                    if (triggers.TryGetValue(name, out var trigger))
                        trigger.IsEnabled = enabled;
            }
            if (restart)
                dispatcher.Start();
            return new { running = dispatcher.IsRunning, assetsReloaded = true };
        }
        finally
        {
            _runtimeMutationLock.Release();
        }
    }

    private MacTriggerDispatcher RequiredTriggerDispatcher() =>
        _triggerDispatcher ?? throw new CapabilityUnavailableException(
            "The macOS trigger dispatcher is unavailable until Core composition completes.");

    private object ListTriggers()
    {
        var triggers = GameTaskManager.TriggerDictionary
            ?? throw new CapabilityUnavailableException(
                "The shared trigger registry is unavailable until core.initialize completes with the platform attached.");
        return triggers
            .OrderByDescending(pair => pair.Value.Priority)
            .Select(pair => new
            {
                name = pair.Key,
                displayName = pair.Value.Name,
                enabled = pair.Value.IsEnabled,
                priority = pair.Value.Priority,
                exclusive = pair.Value.IsExclusive,
                settingsAvailable = _triggerSettings.IsAvailable(pair.Key)
            })
            .ToArray();
    }

    private object SetTriggerEnabled(string name, bool enabled)
    {
        var triggers = GameTaskManager.TriggerDictionary
            ?? throw new CapabilityUnavailableException(
                "The shared trigger registry is unavailable until core.initialize completes with the platform attached.");
        if (!triggers.TryGetValue(name, out var trigger))
            throw new CapabilityUnavailableException($"Trigger '{name}' is not composed in the macOS Core.");
        trigger.IsEnabled = enabled;
        _triggerSettings.SaveEnabled(name, enabled);
        return new { name, enabled = trigger.IsEnabled };
    }

    private static string RequiredString(JObject? parameters, string name) =>
        parameters?.Value<string>(name) is { Length: > 0 } value
            ? value
            : throw new ArgumentException($"{name} is required.");
}

public sealed class CapabilityUnavailableException(string message) : Exception(message);
