using BetterGenshinImpact.Core.Host.Protocol;
using BetterGenshinImpact.Core.Host.Runtime;
using BetterGenshinImpact.Core.Host.Transport;
using Newtonsoft.Json.Linq;
using System.Net.Sockets;
using System.Runtime.Versioning;
using System.Security.Cryptography;
using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.GameLoading;
using BetterGenshinImpact.GameTask.MapMask;

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
    private readonly ScriptRepositoryCatalog _scriptRepositoryCatalog = new(layout);
    private readonly PathingCatalog _pathingCatalog = new(layout);
    private readonly SoloTaskSettingsCatalog _soloTaskSettings = new(layout);
    private readonly TriggerSettingsCatalog _triggerSettings = new(layout);
    private readonly MacroSettingsCatalog _macroSettings = new(layout);
    private NotificationSettingsCatalog? _notificationSettings;
    private readonly PlatformCallbackChannel _platformCallbacks = new();
    private SchedulerCoordinator? _scheduler;
    private readonly CancellationTokenSource _shutdown = new();
    private readonly object _connectionsLock = new();
    private readonly HashSet<Task> _connections = [];
    private MacScriptHostServices? _scriptHostServices;
    private MacScriptServicePlatform? _scriptServicePlatform;
    private MacPathExecutorPlatform? _pathExecutorPlatform;
    private MacMapMaskRuntimePlatform? _mapMaskRuntimePlatform;
    private Func<RuntimeArtifactStatus>? _runtimeArtifactInitializer;
    private RuntimeArtifactStatus? _runtimeArtifactStatus;
    private Action? _platformAssetInitializer;
    private MacTriggerDispatcher? _triggerDispatcher;
    private SoloTaskCoordinator? _soloTasks;
    private KeyMouseScriptCoordinator? _keyMouseScripts;
    private int _platformAssetsInitialized;
    private readonly SemaphoreSlim _runtimeMutationLock = new(1, 1);
    public PlatformCallbackChannel PlatformCallbacks => _platformCallbacks;
    public SoloTaskSettingsCatalog SoloTaskSettings => _soloTaskSettings;
    public TriggerSettingsCatalog TriggerSettings => _triggerSettings;

    private SchedulerCoordinator Scheduler => _scheduler ??= new SchedulerCoordinator(
        layout, _platformCallbacks, sessionToken, _shutdown.Token);
    private SoloTaskCoordinator SoloTasks => _soloTasks ?? throw new CapabilityUnavailableException(
        "Solo task coordinator is unavailable until Core composition completes.");
    private KeyMouseScriptCoordinator KeyMouseScripts => _keyMouseScripts
        ?? throw new CapabilityUnavailableException(
            "Key/mouse script coordinator is unavailable until Core composition completes.");
    private NotificationSettingsCatalog NotificationSettings => _notificationSettings
        ?? throw new CapabilityUnavailableException(
            "Notification settings are unavailable until Core composition completes.");

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

    public void AttachKeyMouseScriptCoordinator(KeyMouseScriptCoordinator coordinator)
    {
        ArgumentNullException.ThrowIfNull(coordinator);
        if (Interlocked.CompareExchange(ref _keyMouseScripts, coordinator, null) is not null)
            throw new InvalidOperationException("Key/mouse script coordinator has already been attached.");
    }

    public void AttachNotificationSettings(NotificationSettingsCatalog settings)
    {
        ArgumentNullException.ThrowIfNull(settings);
        if (Interlocked.CompareExchange(ref _notificationSettings, settings, null) is not null)
            throw new InvalidOperationException("Notification settings have already been attached.");
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
        _pathingCatalog.AttachSettingsUpdated(platform.UpdateConfig);
    }

    public void AttachMapMaskRuntimePlatform(MacMapMaskRuntimePlatform platform)
    {
        ArgumentNullException.ThrowIfNull(platform);
        if (Interlocked.CompareExchange(ref _mapMaskRuntimePlatform, platform, null) is not null)
            throw new InvalidOperationException("MapMask runtime platform has already been attached.");
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
            if (request.Method == "mapMask.catalog")
            {
                return RpcResponse.Success(request.Id,
                    await MapMaskRuntimePlatform.GetPointCatalogAsync(_shutdown.Token));
            }
            if (request.Method == "mapMask.selection.save")
            {
                var selectedTokens = request.Params?["selectedIds"] as JArray
                    ?? throw new ArgumentException("selectedIds is required.");
                var selectedIds = selectedTokens.Select(token => token.Value<string>())
                    .ToArray();
                if (selectedIds.Any(string.IsNullOrWhiteSpace))
                    throw new ArgumentException("selectedIds cannot contain empty values.");
                return RpcResponse.Success(request.Id,
                    await MapMaskRuntimePlatform.SavePointSelectionAsync(
                        selectedIds.Select(id => id!).ToArray(), _shutdown.Token));
            }
            if (request.Method == "keyMouse.stop")
                return RpcResponse.Success(request.Id, await KeyMouseScripts.StopAsync());
            if (request.Method == "notification.test")
                return RpcResponse.Success(request.Id, NotificationSettings.Test());
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
                "catalog.getScriptGroupProjectCommonSettings" => _catalog.GetProjectCommonSettings(
                    RequiredString(request.Params, "name"), RequiredInt(request.Params, "projectIndex")),
                "catalog.saveScriptGroupProjectCommonSettings" => _catalog.SaveProjectCommonSettings(
                    RequiredString(request.Params, "name"), RequiredInt(request.Params, "projectIndex"),
                    RequiredString(request.Params, "status"), request.Params?.Value<bool?>("allowJsNotification"),
                    request.Params?.Value<bool?>("allowJsHttp") ?? false),
                "catalog.getScriptGroupProjectCustomSettings" => _catalog.GetProjectCustomSettings(
                    RequiredString(request.Params, "name"), RequiredInt(request.Params, "projectIndex")),
                "catalog.saveScriptGroupProjectCustomSettings" => _catalog.SaveProjectCustomSettings(
                    RequiredString(request.Params, "name"), RequiredInt(request.Params, "projectIndex"),
                    request.Params?["values"] as JObject ?? throw new ArgumentException("values is required.")),
                "catalog.listScriptGroupAddCandidates" => _catalog.ListAddCandidates(RequiredString(request.Params, "type")),
                "catalog.addScriptGroupProjects" => _catalog.AddProjects(
                    RequiredString(request.Params, "name"), RequiredString(request.Params, "type"),
                    request.Params?["candidateIds"] as JArray ?? [], request.Params?.Value<string>("shellCommand")),
                "catalog.removeScriptGroupProject" => _catalog.RemoveProject(
                    RequiredString(request.Params, "name"), RequiredInt(request.Params, "projectIndex"),
                    request.Params?.Value<bool?>("sameFolder") ?? false),
                "catalog.clearScriptGroup" => _catalog.Clear(RequiredString(request.Params, "name")),
                "catalog.reverseScriptGroup" => _catalog.Reverse(RequiredString(request.Params, "name")),
                "catalog.updateScriptGroupPathingFolders" => _catalog.UpdatePathingFolders(RequiredString(request.Params, "name")),
                "catalog.exportMergedPathing" => _catalog.ExportMergedPathing(RequiredString(request.Params, "name")),
                "catalog.setScriptGroupNextProject" => _catalog.SetNextProject(
                    RequiredString(request.Params, "name"), RequiredInt(request.Params, "projectIndex")),
                "catalog.getScriptGroupProjectLocation" => _catalog.GetProjectLocation(
                    RequiredString(request.Params, "name"), RequiredInt(request.Params, "projectIndex")),
                "catalog.getScriptGroupConfig" => _catalog.GetGroupConfig(RequiredString(request.Params, "name")),
                "catalog.saveScriptGroupConfig" => _catalog.SaveGroupConfig(
                    RequiredString(request.Params, "name"),
                    request.Params?["config"] as JObject ?? throw new ArgumentException("config is required.")),
                "catalog.listScriptProjects" => _scriptProjectCatalog.List(),
                "catalog.getScriptProject" => _scriptProjectCatalog.Get(RequiredString(request.Params, "folderName")),
                "catalog.getScriptProjectRootLocation" => _scriptProjectCatalog.GetRootLocation(),
                "pathing.list" => _pathingCatalog.List(),
                "pathing.detail" => _pathingCatalog.GetDetail(
                    RequiredString(request.Params, "id")),
                "pathing.rootLocation" => _pathingCatalog.GetRootLocation(),
                "pathing.delete" => _pathingCatalog.Delete(
                    RequiredString(request.Params, "id")),
                "pathing.settings.get" => _pathingCatalog.GetSettings(),
                "pathing.settings.save" => _pathingCatalog.SaveSettings(
                    request.Params?["settings"] as JObject
                    ?? throw new ArgumentException("settings is required.")),
                "pathing.run" => Scheduler.RunProject(
                    _pathingCatalog.BuildProject(RequiredString(request.Params, "id")),
                    $"地图追踪:{RequiredString(request.Params, "id")}"),
                "repository.state" => _scriptRepositoryCatalog.GetState(),
                "repository.update" => await _scriptRepositoryCatalog.UpdateAsync(
                    RequiredString(request.Params, "channel"),
                    RequiredString(request.Params, "url"),
                    _shutdown.Token),
                "repository.reset" => ResetScriptRepository(),
                "repository.web.getRepoJson" => _scriptRepositoryCatalog.GetRepoJson(),
                "repository.web.getSubscribedScriptPaths" => _scriptRepositoryCatalog.GetSubscribedPathsJson(),
                "repository.web.importUri" => await _scriptRepositoryCatalog.ImportUriAsync(
                    RequiredString(request.Params, "uri"), _shutdown.Token),
                "repository.web.getFile" => _scriptRepositoryCatalog.GetFile(
                    RequiredString(request.Params, "path")),
                "repository.web.updateSubscribed" => _scriptRepositoryCatalog.ResetUpdateFlag(
                    RequiredString(request.Params, "path")),
                "repository.web.clearUpdate" => _scriptRepositoryCatalog.ClearUpdateFlags(),
                "repository.web.getGuideStatus" => _scriptRepositoryCatalog.GetGuideStatus(),
                "repository.web.setGuideStatus" => _scriptRepositoryCatalog.SetGuideStatus(
                    request.Params?.Value<bool?>("status")
                    ?? throw new ArgumentException("status is required.")),
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
                "mapMask.settings.get" => _triggerSettings.GetMapMaskPickerSettings(),
                "mapMask.settings.save" => _triggerSettings.SaveMapMaskPickerSettings(
                    request.Params?["settings"] as JObject
                    ?? throw new ArgumentException("settings is required.")),
                "mapMask.selection.get" => MapMaskRuntimePlatform.GetPointSelection(),
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
                "keyMouse.list" => KeyMouseScripts.List(),
                "keyMouse.rootLocation" => KeyMouseScripts.RootLocation(),
                "keyMouse.saveRecording" => KeyMouseScripts.SaveRecording(
                    request.Params?["events"] as JArray
                    ?? throw new ArgumentException("events is required."),
                    request.Params?["info"] as JObject
                    ?? throw new ArgumentException("info is required.")),
                "keyMouse.rename" => KeyMouseScripts.Rename(
                    RequiredString(request.Params, "id"),
                    RequiredString(request.Params, "name")),
                "keyMouse.delete" => KeyMouseScripts.Delete(
                    RequiredString(request.Params, "id")),
                "keyMouse.play" => KeyMouseScripts.Start(
                    RequiredString(request.Params, "id")),
                "keyMouse.status" => KeyMouseScripts.Status(),
                "notification.settings.get" => NotificationSettings.Get(),
                "notification.settings.save" => NotificationSettings.Save(
                    request.Params?["settings"] as JObject
                    ?? throw new ArgumentException("settings is required.")),
                "macro.settings.get" => _macroSettings.Get(),
                "macro.settings.save" => _macroSettings.Save(
                    request.Params?["settings"] as JObject
                    ?? throw new ArgumentException("settings is required.")),
                "runtime.status" => RuntimeStatus(),
                "scheduler.run" => Scheduler.Run(RequiredString(request.Params, "groupName")),
                "scheduler.runGroups" => Scheduler.RunGroups(
                    RequiredStrings(request.Params, "groupNames")),
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

    private MacMapMaskRuntimePlatform MapMaskRuntimePlatform =>
        _mapMaskRuntimePlatform ?? throw new CapabilityUnavailableException(
            "MapMask runtime platform is unavailable until Core composition completes.");

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
                "catalog.script-group-editing",
                "catalog.script-repository",
                "pathing.catalog",
                "runtime-layout",
                "runtime-artifacts.source-lock",
                "opencv",
                "clearscript-v8",
                "trigger-control",
                "runtime-control",
                "runtime.geometry-refresh",
                "scheduler.run",
                "scheduler.runGroups",
                "keyMouse.recording",
                "keyMouse.playback",
                "notification.native",
                "macro.hold-continuation"
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
        if (_platformCallbacks.IsAttached)
            _mapMaskRuntimePlatform?.Initialize();
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
            if (_scheduler is not null)
                await _scheduler.StopActiveAsync(cancellationToken);
            if (_soloTasks is not null)
                await _soloTasks.StopActiveAsync(cancellationToken);
            if (_keyMouseScripts is not null)
                await _keyMouseScripts.StopAsync();
            await RequiredTriggerDispatcher().StopAsync(cancellationToken);
            return RuntimeStatus();
        }
        finally
        {
            _runtimeMutationLock.Release();
        }
    }

    private object RuntimeStatus() => new
    {
        running = RequiredTriggerDispatcher().IsRunning,
        mapMask = _mapMaskRuntimePlatform?.GetStatus(),
        mapMaskTrigger = GameTaskManager.TriggerDictionary?.GetValueOrDefault("MapMask")
            is MapMaskTrigger trigger ? trigger.GetRuntimeStatus() : null
    };

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
                await dispatcher.StopAsync(cancellationToken);

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
        var autoHangoutEventEnabled = _triggerSettings.GetAutoHangoutEventEnabled();
        return triggers
            .OrderByDescending(pair => pair.Value.Priority)
            .Select(pair => new
            {
                name = pair.Key,
                displayName = pair.Value.Name,
                enabled = pair.Value.IsEnabled,
                canSetEnabled = CanSetTriggerEnabled(pair.Value),
                priority = pair.Value.Priority,
                exclusive = pair.Value.IsExclusive,
                settingsAvailable = _triggerSettings.IsAvailable(pair.Key),
                autoHangoutEventEnabled = pair.Key == "AutoSkip"
                    ? autoHangoutEventEnabled
                    : (bool?)null
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
        if (!CanSetTriggerEnabled(trigger))
            throw new CapabilityUnavailableException(
                $"Trigger '{name}' is controlled by its upstream configuration and cannot be toggled directly.");
        trigger.IsEnabled = enabled;
        _triggerSettings.SaveEnabled(name, enabled);
        return new { name, enabled = trigger.IsEnabled };
    }

    private static bool CanSetTriggerEnabled(ITaskTrigger trigger) =>
        trigger is not GameLoadingTrigger;

    private static string RequiredString(JObject? parameters, string name) =>
        parameters?.Value<string>(name) is { Length: > 0 } value
            ? value
            : throw new ArgumentException($"{name} is required.");

    private static int RequiredInt(JObject? parameters, string name) =>
        parameters?.Value<int?>(name) ?? throw new ArgumentException($"{name} is required.");

    private static string[] RequiredStrings(JObject? parameters, string name)
    {
        var values = parameters?[name] as JArray
            ?? throw new ArgumentException($"{name} is required.");
        var result = values.Select(value => value.Value<string>()).ToArray();
        if (result.Length == 0 || result.Any(string.IsNullOrWhiteSpace))
            throw new ArgumentException($"{name} must contain at least one non-empty string.");
        return result.Select(value => value!).ToArray();
    }

    private object ResetScriptRepository()
    {
        _scriptRepositoryCatalog.ResetAsync(_shutdown.Token).GetAwaiter().GetResult();
        return new { reset = true };
    }
}

public sealed class CapabilityUnavailableException(string message) : Exception(message);
