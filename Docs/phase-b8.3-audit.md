# B8.3 Audit: AutoPickConfig Runtime Reads

**Status:** Audit only — no code changes
**Predecessor:** B8.2 complete (commit `d330b01`, Core Verification 90/90)

---

## 1. All AutoPickConfig Read Sites

### 1.1 AutoPickTrigger.Init() (one-time at trigger init)

| Line | Code | Field | Dynamic? |
|------|------|-------|----------|
| 93-94 | `var config = _configProvider?.AutoPickConfig ?? TaskContext.Instance().Config.AutoPickConfig` | Config object reference | **Live** — `AutoPickConfig` is a mutable ObservableObject; reads its properties at this point |
| 97 | `config.BlackListEnabled` | bool | **Init-time** — controls whether blacklist files are loaded. Changing after Init has no effect |
| 109 | `config.WhiteListEnabled` | bool | **Init-time** — controls whether whitelist files are loaded. Changing after Init has no effect |

These are already using the fallback chain from B7: `_configProvider` wins if non-null.

### 1.2 AutoPickTrigger.OnCapture() (every capture frame)

| Line | Code | Field | Current source | Dynamic? |
|------|------|-------|----------------|----------|
| 221 | `var config = TaskContext.Instance().Config.AutoPickConfig` | Config object reference | **Static TaskContext** | **Live** — the config object is mutable and read each frame |
| 233 | `config.ItemIconLeftOffset * scale` | int | Static TaskContext | **Live** — offset read every frame |
| 234 | `config.ItemTextLeftOffset * scale` | int | Static TaskContext | **Live** |
| 254 | `config.WhiteListEnabled` | bool | Static TaskContext | **Live** |
| 260 | `config.BlackListEnabled` | bool | Static TaskContext | **Live** |
| 267 | `config.FastModeEnabled` (commented out) | bool | Static TaskContext | — (dead code) |
| 281 | `config.ItemTextLeftOffset * scale` | int | Static TaskContext | **Live** |
| 282 | `config.ItemTextRightOffset * scale` | int | Static TaskContext | **Live** |
| 300 | `config.OcrEngine` | enum string | Static TaskContext | **Live** |
| 358 | `config.WhiteListEnabled` | bool | Static TaskContext | **Live** |
| 373 | `config.BlackListEnabled` | bool | Static TaskContext | **Live** |

**Total: 10 live OnCapture reads** from `TaskContext.Instance().Config.AutoPickConfig`, all replaceable by `_configProvider.AutoPickConfig`.

---

## 2. Live vs Snapshot Decision

### Current behavior (upstream)

`TaskContext.Instance().Config.AutoPickConfig` returns the SAME `AutoPickConfig` ObservableObject instance every call. Upstream UI writes go directly to this object's properties. OnCapture reads them live — no caching, no snapshot.

This means if the user changes "ItemIconLeftOffset" in the settings UI while AutoPick is running, OnCapture picks it up the next frame.

### Proposed behavior

Replace `TaskContext.Instance().Config.AutoPickConfig` with `_configProvider.AutoPickConfig`.

Since `IAutoPickConfigProvider` contract already states:
> AutoPickConfig returns the **same mutable reference** as the upstream config object.

...and `WindowsAutoPickConfigProvider` does exactly that:
```csharp
public AutoPickConfig AutoPickConfig => GameTask.TaskContext.Instance().Config.AutoPickConfig;
```

...this preserves **live-read semantics**. No snapshot, no stale copy.

### Conclusion: Live reads via provider, not TaskContext.

The change is purely an access-path change (which object to read), not a semantics change.

---

## 3. `_configProvider` Nullability

### Current state

`_configProvider` is `IAutoPickConfigProvider?` (nullable), with fallback:
```csharp
var config = _configProvider?.AutoPickConfig
             ?? TaskContext.Instance().Config.AutoPickConfig;
```

### Production callers after B8.2

| Caller | Passes configProvider? | Production? |
|--------|-----------------------|-------------|
| `GameTaskManager.LoadInitialTriggers(inputBackend, systemInfo, configProvider)` → `new AutoPickTrigger(..., configProvider)` | **Yes** | Windows startup |
| `GameTaskManager.AddTrigger(name, ..., systemInfo)` → `new AutoPickTrigger(..., null)` | **No** (passes null) | Windows script dynamic add |
| `MacAutoPickComposition.Compose(provider, state, backend, systemInfo, extConfig)` | **Yes** | macOS startup |
| Verification tests | Sometimes | Test |

### Decision: B8.3 should make `configProvider` required

- `MacAutoPickComposition` already passes it
- `LoadInitialTriggers` already receives and passes it
- `AddTrigger` does NOT currently have it (the `configProvider` parameter was removed in B8.2c)

**Action needed:** Restore `IAutoPickConfigProvider` parameter to `GameTaskManager.AddTrigger` and `TaskTriggerDispatcher.AddTrigger`, so `AutoPickTrigger` is never constructed without a configProvider. This eliminates the `?? TaskContext.Instance()` fallback entirely.

---

## 4. AutoPickExternalConfig — Separate Responsibility

`AutoPickExternalConfig` is an optional script-layer override:

| Field | Purpose |
|-------|---------|
| `TextList` | White-listed "F" target texts |
| `ForceInteraction` | Press F regardless of visual context |

This is NOT AutoPickConfig — it's a per-script timer config. It lives alongside AutoPickConfig but does NOT overlap:
- No PickKey
- No offsets
- No OCR engine
- No blacklist/whitelist toggles

**They are orthogonal and should stay separate.** The trigger constructor correctly receives both as independent params.

---

## 5. Construction Chain Audit

### 5.1 Windows

**Route: `TaskTriggerDispatcher.Start()` → `GameTaskManager.LoadInitialTriggers()` → `new AutoPickTrigger(...)`**

```
LoadInitialTriggers(IInputBackend, ISystemInfo, IAutoPickConfigProvider)
  → ReloadAssets()
  → AutoPickAssets.Initialize(systemInfo, configProvider)
  → new AutoPickTrigger(null, null, configProvider, inputBackend, systemInfo)
```

ConfigProvider **present** ✅.

**Route: `TaskTriggerDispatcher.AddTrigger()` → `GameTaskManager.AddTrigger()` → `new AutoPickTrigger(...)`**

```
AddTrigger("AutoPick", externalConfig, inputBackend, systemInfo)
  → new AutoPickTrigger(externalConfig, null, null, inputBackend, systemInfo)
```

ConfigProvider **missing** ❌ — null is passed. This path needs the configProvider parameter restored.

### 5.2 macOS

**Route: `MacAutoPickComposition.Compose()`**

```
Compose(configProvider, runtimeState, inputBackend, systemInfo, externalConfig)
  → AutoPickAssets.Initialize(systemInfo, configProvider)
  → new AutoPickTrigger(externalConfig, runtimeState, configProvider, inputBackend, systemInfo)
```

ConfigProvider **present** ✅.

### 5.3 Tests

| # | Constructor call | ConfigProvider | Notes |
|---|-----------------|----------------|-------|
| 1-6 | B5 tests | null | Init not called; StopCount/field reflection only |
| 7 | B6 cleanup | null | Uses provider from Initialize |
| 8 | B7 Compose calls | via Compose | AutoPickAssets.Initialize uses provider |
| 9 | B8.2 AddTrigger test | null | Init not called; tests manager path |
| 10 | B8.2 AddTrigger-style test | b82Prov | Has config provider |

---

## 6. Minimum B8.3 Implementation Scope

| Change | Required | Files |
|--------|----------|-------|
| OnCapture: `configProvider.AutoPickConfig` replaces `TaskContext.Instance().Config.AutoPickConfig` | Required | `AutoPickTrigger.cs` |
| `configProvider` becomes required (non-nullable) in master constructor | Required | `AutoPickTrigger.cs` |
| Re-add `IAutoPickConfigProvider` to `GameTaskManager.AddTrigger` | Required | `GameTaskManager.cs` |
| Re-add `IAutoPickConfigProvider` to `TaskTriggerDispatcher.AddTrigger` | Required | `TaskTriggerDispatcher.cs` |
| Remove `?? TaskContext.Instance()` fallback from Init() | Required | `AutoPickTrigger.cs` |
| Keep `?? TaskContext.Instance()` fallback in OnCapture for legacy? | **Remove entirely** — all production paths now supply provider | `AutoPickTrigger.cs` |
| Verify tests pass with non-null provider | Required | `Program.cs` |

### Specific code changes

**AutoPickTrigger.cs:**
```csharp
// Field becomes non-nullable
private readonly IAutoPickConfigProvider _configProvider;

// Constructor validates
public AutoPickTrigger(..., IAutoPickConfigProvider configProvider, ...)
{
    ArgumentNullException.ThrowIfNull(configProvider);
    _configProvider = configProvider;
    ...
}

// Init()
var config = _configProvider.AutoPickConfig;
// No TaskContext fallback
// (BlackListEnabled/WhiteListEnabled reads remain by-value from Init snapshot)

// OnCapture() line 221
var config = _configProvider.AutoPickConfig;
// No TaskContext fallback — same live semantics
```

**GameTaskManager.AddTrigger — restore configProvider:**
```csharp
public static bool AddTrigger(
    string name, object? externalConfig,
    IInputBackend inputBackend, ISystemInfo systemInfo,
    IAutoPickConfigProvider autoPickConfigProvider)
{
    ...
    case "AutoPick":
        trigger = new AutoPickTrigger(externalConfig, null,
            autoPickConfigProvider, inputBackend, systemInfo);
```

**TaskTriggerDispatcher.AddTrigger — forward configProvider:**
```csharp
public bool AddTrigger(string name, object? externalConfig)
{
    lock (_triggerListLocker)
    {
        if (GameTaskManager.AddTrigger(name, externalConfig,
            _inputBackend, RequireSystemInfo(), _autoPickConfigProvider))
```

---

## 7. Verification Plan

| # | Test | Assertion |
|---|------|-----------|
| B8.3.1 | OnCapture reads config from provider, not TaskContext | Inject provider with `ItemIconLeftOffset = 99`; OnCapture uses it |
| B8.3.2 | null configProvider → ArgumentNullException | Master ctor rejects null |
| B8.3.3 | Init skips whitelist when provider says disabled | Provider.WhiteListEnabled=false → `_whiteList` empty |
| B8.3.4 | Init skips blacklist when provider says disabled | Same |
| B8.3.5 | Live config mutation reflected in OnCapture | Change provider's AutoPickConfig property between reads |
| B8.3.6 | AddTrigger with configProvider restores path | Verify trigger constructed with non-null provider |

---

## 8. Out of Scope

| NOT in B8.3 | Reason |
|-------------|--------|
| OCR gateway (OcrFactory.Paddle, TextInferenceFactory) | B9 |
| Input backend | B8.1 done |
| ISystemInfo | B8.2 done |
| Expand Core shim GameTaskManager | B8.2 done, explicitly limited |
| AutoPickExternalConfig refactoring | Separate concern, orthogonal |
| Full WPF build | Manual/stage-closeout only |
| Shim deletion | B10 |
