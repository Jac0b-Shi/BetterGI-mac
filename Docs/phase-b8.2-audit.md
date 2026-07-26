# B8.2 Audit: AssetScale / SystemInfo Reads in AutoPick

**Status:** Audit only — no code changes
**Predecessor:** B8.1.1 complete (commit `47e36c7`)

---

## 1. All AssetScale / SystemInfo Reads in AutoPick

### 1.1 AutoPickTrigger.OnCapture() — runtime AssetScale read

| File:line | Code | Semantic |
|-----------|------|----------|
| `AutoPickTrigger.cs:215` | `TaskContext.Instance().SystemInfo.AssetScale` | Responsive layout scaling factor: `1080P_width / actual_width` (max 1.0). Used to scale pixel offset coordinates for non-1080p resolutions. |

**Usage in OnCapture (all are offsets derived from `scale`):**

| Line | Expression | What it scales |
|------|-----------|----------------|
| 226 | `config.ItemIconLeftOffset * scale` | Horizontal start of item icon region |
| 228 | `config.ItemTextLeftOffset * scale` | Horizontal start of item text region |
| 228 | `config.ItemIconLeftOffset * scale` | Subtract from above to get icon width |
| 275 | `config.ItemTextLeftOffset * scale` | Horizontal start of OCR text region |
| 276 | `config.ItemTextRightOffset * scale` | Width of OCR text region |

These are all pixel-offset calculations. `scale` is a derived multiplier — not a system capability.
The config values (`ItemIconLeftOffset` etc.) are 1080p-relative; `scale` adjusts them to the actual game resolution.

### 1.2 AutoPickAssets — template ROI AssetScale reads (via BaseAssets)

`AutoPickAssets` extends `BaseAssets<AutoPickAssets>` which provides:
- `AssetScale` property → `systemInfo.AssetScale`
- `CaptureRect` property → `systemInfo.ScaleMax1080PCaptureRect`

`systemInfo` is initialized via `BaseAssets()` constructor → `TaskContext.Instance().SystemInfo`.

**16 AssetScale references in template ROI definitions:**

| File:line | Expression | Description |
|-----------|-----------|-------------|
| `AutoPickAssets.cs:51-54` | `(int)(1090 * AssetScale)`, `(330 * AssetScale)`, `(60 * AssetScale)`, `(420 * AssetScale)` | FRo ROI |
| `AutoPickAssets.cs:85-88` | `CaptureRect.Width-(110 * AssetScale)`, `(550 * AssetScale)`, `(70 * AssetScale)`, `(100 * AssetScale)` | LRo ROI |
| `AutoPickAssets.cs:157-160` | `(1090 * AssetScale)`, `(330 * AssetScale)`, `(60 * AssetScale)`, `(420 * AssetScale)` | Custom pick key ROI (LoadCustomPickKey) |
| `AutoPickAssets.cs:172-175` | `(1200 * AssetScale)`, `(350 * AssetScale)`, `(50 * AssetScale)`, `... - (220 * AssetScale) - (350 * AssetScale)` | Chat pick key ROI (LoadCustomChatPickKey) |

All 16 uses are ROI pixel offsets in the template-only constructor. They are multiplied by `AssetScale` to adjust 1080p-relative coordinates to the actual game resolution.

### 1.3 AssetScale Formula

```
AssetScale = min(actual_game_width / 1920d, 1.0)
```

Examples:
- Game width 1280 → AssetScale = 1280/1920 = 0.6667 (ROIs scaled down)
- Game width 1920 → AssetScale = 1920/1920 = 1.0 (native 1080p, no scaling)
- Game width 2560 → AssetScale = min(2560/1920, 1.0) = 1.0 (capped — ROIs not expanded beyond 1080p layout)

ROI positions defined in 1080p-relative pixels are multiplied by AssetScale to fit the actual game resolution. This multiplier is always ≤ 1.0 — it never upscales ROIs beyond the 1080p template.

---

## 2. ISystemInfo Interface Audit

### 2.1 Current interface (`BetterGenshinImpact/GameTask/Model/ISystemInfo.cs`)

| Member | Type | AutoPick uses | Platform-specific |
|--------|------|---------------|-------------------|
| `DisplaySize` | `Size` | No | **Win32** (PrimaryScreen) |
| `GameScreenSize` | `BgiRect` | No | **Win32** (GetGameScreenRect) |
| `AssetScale` | `double` | **Yes** (17 refs) | Derived (width ratio) — not platform-specific |
| `ZoomOutMax1080PRatio` | `double` | No | Derived |
| `ScaleTo1080PRatio` | `double` | No | Derived |
| `CaptureAreaRect` | `BgiRect` | No | **Win32** |
| `ScaleMax1080PCaptureRect` | `BgiRect` | Used by AutoPickAssets' `CaptureRect` prop | Derived from CaptureAreaRect |
| `GameProcess` | `Process?` | No | **Win32** |
| `GameProcessName` | `string` | No | **Win32** |
| `GameProcessId` | `int` | No | **Win32** |
| `DesktopRectArea` | `DesktopRegion` | No | **Win32** (wraps input) |

### 2.2 Windows implementation (`SystemInfo`, line 60-103)

- Constructor takes `IntPtr hWnd` — fundamentally Win32
- Computes `AssetScale` = `GameScreenSize.Width / 1920d` (capped at 1.0)
- Computes `ScaleTo1080PRatio` = `GameScreenSize.Width / 1920d`
- Computes `ScaleMax1080PCaptureRect` from `CaptureAreaRect`

### 2.3 macOS shim (`MacSystemInfo`, via `Shim/TaskContext.cs`)

- `Shim/TaskContext.Instance().SystemInfo` = `new MacSystemInfo()` (default)
- `MacSystemInfo` uses hardcoded/game-metrics values
- AssetScale = same width/1920d formula, but from macOS window metrics

### 2.4 DI/Composition path

| Platform | ISystemInfo creation |
|----------|---------------------|
| Windows | `TaskContext.Instance().Init(hWnd)` → `new SystemInfo(hWnd)` |
| macOS | `Shim/TaskContext.Instance().SystemInfo` = `new MacSystemInfo(...)` — set before Compose |

---

## 3. AutoPick-Specific Requirement

### 3.1 What AutoPick actually needs from system info

| Consumer | What it reads | Value range | Purpose |
|----------|--------------|-------------|---------|
| `AutoPickTrigger.OnCapture` | `AssetScale` (double) | 0.0–1.0 | Scale 1080p-relative offsets to actual resolution |
| `AutoPickAssets` (16 refs) | `AssetScale` (double) | 0.0–1.0 | Same — template ROI calibration |
| `AutoPickAssets` | `CaptureRect` (via `ScaleMax1080PCaptureRect`) | `Rect` | Template LRo ROI reference — uses `CaptureRect.Width` and `CaptureRect.Height` |

AutoPick does NOT need:
- `DisplaySize`, `GameScreenSize`, `GameProcess`, `DesktopRectArea`
- Process info, HWND, or display info

### 3.2 Can existing ISystemInfo cover AutoPick?

**Yes, trivially.** `AssetScale` is already a member of `ISystemInfo`. The issue is not interface design — it's the **access path** (`TaskContext.Instance().SystemInfo.AssetScale`).

### 3.3 Should ISystemInfo be injected into AutoPickTrigger?

**Option A: Inject existing ISystemInfo**

```csharp
public AutoPickTrigger(
    AutoPickExternalConfig? config,
    IAutoPickRuntimeState? runtimeState,
    IAutoPickConfigProvider? configProvider,
    IInputBackend inputBackend,
    ISystemInfo systemInfo)
```

- `_systemInfo = systemInfo`
- In `OnCapture()`: `var scale = _systemInfo.AssetScale`
- Windows: `TaskTriggerDispatcher` passes `TaskContext.Instance().SystemInfo`
- macOS: `MacAutoPickComposition.Compose()` passes `MacSystemInfo`

**Pros:** Uses existing interface — no new abstraction.
**Cons:** Adds another constructor param. ISystemInfo exposes 11 members but AutoPick only uses 1. `ISystemInfo` is currently compiled via Link into Core's Shim only; making it available as an injection parameter requires either:
- WPF project to reference it (already does, since SystemInfo.cs is a native file in `BetterGenshinImpact/GameTask/Model/`)
- Core project to link `ISystemInfo.cs` and `SystemInfo.cs` (or at least the interface)

**Option B: Inject only AssetScale value**

```csharp
public AutoPickTrigger(
    ...,
    double assetScale)
```

- Simplest possible injection
- But asset scale may change at runtime (window resize?) — unlikely but the upstream code doesn't handle it either
- Also: AutoPickAssets needs AssetScale at CONSTRUCTION time, not just trigger runtime
- Means two separate injection points

**Option C: Create `IAutoPickScaleProvider`**

```csharp
public interface IAutoPickScaleProvider
{
    double AssetScale { get; }
    BgiRect CaptureRect { get; }  // needed by AutoPickAssets
}
```

- Over-engineered for a single double value + one Rect

### 3.4 Recommendation

**Inject existing `ISystemInfo` into AutoPickTrigger (Option A).**

Rationale:
- AutoPick uses exactly one member (`AssetScale`) and one derived property (`ScaleMax1080PCaptureRect`)
- ISystemInfo is already the canonical source for AssetScale on both platforms
- Creating a narrower interface adds abstraction overhead with no practical benefit for a single double

**AutoPickAssets requires a separate dedicated initialization path** — see §5.2 below. The singleton construction timing makes ISystemInfo injection via `Configure()` impossible after construction.

---

## 4. Construction Points for ISystemInfo Injection

### 4.1 Windows production callers

| Caller | Current SystemInfo source | Change needed |
|--------|--------------------------|---------------|
| `TaskTriggerDispatcher.Start()` → ... | `TaskContext.Instance().SystemInfo` | Dispatcher reads SystemInfo inside Start() after TaskContext.Init(hWnd); stores as `_systemInfo`. Passes to LoadInitialTriggers. |
| `GameTaskManager.LoadInitialTriggers(IInputBackend, ISystemInfo)` → trigger | Via `AutoPickTrigger.OnCapture` at runtime | Accept `ISystemInfo` param; pass to trigger constructor |
| `GameTaskManager.AddTrigger(name, config, inputBackend, systemInfo)` → trigger | Same | Same |
| `AutoPickAssets.Initialize(systemInfo, configProvider)` | `TaskContext.Instance().SystemInfo` | Only via dedicated Initialize path — not Configure() |
| `AutoPickAssets` template ROIs | via `systemInfo.AssetScale` | No change — systemInfo is already available via parameterized ctor |

### 4.2 macOS composition

| Caller | Current SystemInfo source | Change needed |
|--------|--------------------------|---------------|
| `MacAutoPickComposition.Compose()` | `MacSystemInfo` via shim `TaskContext.Instance()` | Accept `ISystemInfo` param; pass to trigger + assets |
| AutoPickAssets (macOS) | `BaseAssets<T>` → `Shim/TaskContext` | Pass ISystemInfo during Configure() or new overload |

### 4.3 Tests

| Caller | Change |
|--------|--------|
| All `new AutoPickTrigger(...)` calls | Add ISystemInfo param (use existing `MacSystemInfo` or test mock) |
| All `MacAutoPickComposition.Compose(...)` calls | Same |
| AutoPickAssets.Configure() tests | No change if systemInfo is separte; or add to Configure() |

---

## 5. B8.2 Design

### 5.1 AutoPickTrigger

**Add to constructor:**
```csharp
private readonly ISystemInfo _systemInfo;

public AutoPickTrigger(
    AutoPickExternalConfig? config,
    IAutoPickRuntimeState? runtimeState,
    IAutoPickConfigProvider? configProvider,
    IInputBackend inputBackend,
    ISystemInfo systemInfo)
{
    ArgumentNullException.ThrowIfNull(inputBackend);
    ArgumentNullException.ThrowIfNull(systemInfo);
    ...
    _systemInfo = systemInfo;
}
```

**Replace OnCapture line 215:**
```csharp
// Before:
var scale = TaskContext.Instance().SystemInfo.AssetScale;
// After:
var scale = _systemInfo.AssetScale;
```

### 5.2 AutoPickAssets — Dedicated Initialization Path

**NOT viable:** `Configure(ISystemInfo)` after construction, `SetSystemInfo()`, or modifying `Singleton<T>`/`BaseAssets<T>`.

**Reason:** `BaseAssets<T>.systemInfo` is `readonly`, initialized in the constructor.
AutoPickAssets' template ROIs read `AssetScale` and `CaptureRect` during construction.
By the time `Configure()` is called, these values are already consumed. Post-hoc injection is impossible.

**Solution: private parameterized constructor + static `Initialize()` + hidden `Instance`**

```csharp
// AutoPickAssets: private constructor accepting ISystemInfo
private AutoPickAssets(ISystemInfo systemInfo)
    : base(systemInfo)
{
    // Copy of existing template-only ctor body (FRo, ChatIconRo, SettingsIconRo, LRo)
}

private static readonly object InitializationLock = new();

/// <summary>Sole initialization entry point. Must be called once before Instance.</summary>
public static void Initialize(
    ISystemInfo systemInfo,
    IAutoPickConfigProvider configProvider)
{
    ArgumentNullException.ThrowIfNull(systemInfo);
    ArgumentNullException.ThrowIfNull(configProvider);
    lock (InitializationLock)
    {
        if (_instance != null)
            throw new InvalidOperationException(
                "AutoPickAssets is already initialized. Call DestroyInstance() first.");
        var instance = new AutoPickAssets(systemInfo);
        instance.Configure(configProvider);
        _instance = instance;
    }
}

/// <summary>
/// Hidden static property. Does NOT fall back to Activator/parameterless constructor.
/// Throws if Initialize() has not been called.
/// </summary>
public new static AutoPickAssets Instance =>
    _instance ?? throw new InvalidOperationException(
        "AutoPickAssets.Initialize(...) must be called before Instance.");
```

**Initialization sequence:**
1. `ISystemInfo` → passed to parameterized `AutoPickAssets(systemInfo)` constructor
2. `BaseAssets(ISystemInfo)` → sets `this.systemInfo` (readonly, now correct)
3. Template ROI expressions evaluate `AssetScale` and `CaptureRect` correctly
4. `Configure(configProvider)` → handles config-dependent assets (PickRo, PickVk, ChatPickRo)
5. Singleton published as `_instance`

**Lifecycle:**
- `Initialize()` = only way to publish instance; single-call guard
- `Instance` = hidden getter; throws if never initialized
- `DestroyInstance()` → clears `_instance` → next `Instance` access **throws** (no silent fallback)
- Re-initialize requires explicit `DestroyInstance()` + `Initialize()` again
- Parameterless constructor may remain in source for legacy compatibility but `Instance` will NOT call it
- `EnsureConfigured()` (existing) gates on `_configured` flag — will also fail since `Instance` throws first

**Contrast with old design (withdrawn):**
- No `lock (syncRoot ??= new())` — race condition risk eliminated
- No `override Instance` — static properties cannot be overridden
- No "depending on context" fallback to parameterless constructor — clear deterministic failure
- No modification to `BaseAssets<T>` or `Singleton<T>`

### 5.3 Windows Lifecycle — dispatcher does NOT hold ISystemInfo

**Confirmed:** `TaskTriggerDispatcher` constructor runs BEFORE `Start(hWnd, mode)`. `SystemInfo` is created inside `Start()` at line 147:
```
TaskContext.Instance().Init(hWnd);
```
At dispatcher construction time, no valid SystemInfo exists. **Do not inject ISystemInfo into dispatcher constructor.**

**Windows chain (corrected):**

**No need to receive ISystemInfo at dispatcher construction time.** Instead:

```
TaskTriggerDispatcher.Start(hWnd, mode)
  ├─ TaskContext.Instance().Init(hWnd)           // creates SystemInfo
  ├─ _systemInfo = TaskContext.Instance().SystemInfo  // stored
  ├─ AutoPickAssets.Initialize(                  // NEW: dedicated init
  │     _systemInfo,
  │     _autoPickConfigProvider)
  ├─ GameTaskManager.LoadInitialTriggers(
  │     _inputBackend,
  │     _systemInfo)                             // pass stored ISystemInfo
  │   └─ new AutoPickTrigger(..., systemInfo)
  └─ ...
```

**ReloadInitialTriggers() — uses stored reference, no fallback:**
```csharp
public void ReloadInitialTriggers()
{
    var si = RequireSystemInfo();
    SetTriggers(GameTaskManager.LoadInitialTriggers(_inputBackend, si));
}

private ISystemInfo RequireSystemInfo() =>
    _systemInfo ?? throw new InvalidOperationException(
        "TaskTriggerDispatcher.Start() must be called first.");
```

- Called from `TaskRunner.End()` — after `Start()`, so `_systemInfo` already set
- If called before `Start()`: **throws `InvalidOperationException`**
- No fallback to shim/default SystemInfo
- No silent re-read of `TaskContext.Instance()`

### 5.4 macOS composition

`MacAutoPickComposition.Compose()` receives `ISystemInfo` from the host and:

1. Creates `AutoPickAssets` via dedicated `Initialize(systemInfo, configProvider)` — no `TaskContext.Instance()` fallback
2. Passes `ISystemInfo` to `AutoPickTrigger(..., systemInfo)`
3. All ROIs use the provided systemInfo, not the shim singleton

---

## 6. Minimum Scope for B8.2

| Change | Required | Files |
|--------|----------|-------|
| AutoPickTrigger adds ISystemInfo param | Required | `AutoPickTrigger.cs` |
| OnCapture uses `_systemInfo.AssetScale` instead of `TaskContext.Instance()` | Required | `AutoPickTrigger.cs` |
| GameTaskManager.LoadInitialTriggers/AddTrigger accept ISystemInfo | Required | `GameTaskManager.cs` |
| TaskTriggerDispatcher forwards ISystemInfo | Required | `TaskTriggerDispatcher.cs` |
| MacAutoPickComposition.Compose accepts ISystemInfo | Required | `MacAutoPickComposition.cs` |
| AutoPickAssets receives ISystemInfo via dedicated Initialize() | Required | `AutoPickAssets.cs` |
| Core csproj links ISystemInfo | If not already linked | `.csproj` |
| Verification tests update | Required | `Program.cs` |

## 7. Out of Scope

| NOT in B8.2 | Reason |
|-------------|--------|
| AutoPickConfig runtime reads (offsets, OCR engine, enabled flags) | B8.3 |
| Input backend | B8.1 done |
| OCR/Yap static gateways | B9 |
| DpiScale (used in GameCaptureRegion/other tasks) | Not an AutoPick dependency |
| Remove DpiScale from TaskContext | Not an AutoPick concern |
| Full WPF compatibility backlog | Restoration phase |
| Shim deletion | B10 |

---

## 8. B8.1 Commit Chain — Key Implementation Nodes

**Not a complete chain** — only the primary implementation and fix commits.

### B8.1.0 series (Win32InputBackend + gate)
- `e6c3495` — B8.1.0: Win32InputBackend + helpers
- `0b93346` — Layering: helpers moved from Core to WPF
- `7777b26` — Scroll helper cleanup
- `698efff` — Using fix, adapter-gate CI, 146-error classification
- `fc5ff09` — csproj duplicate Compile fix
- `c7d4d61` — verification using fix
- `3e25a80` — Exe→Library fix (gate passes)

### B8.1.1 (AutoPick IInputBackend injection)
- `47e36c7` — B8.1.1: trigger + dispatcher + GameTaskManager + MacComposition

---

## 9. B8.2 Closeout

### Commit chain

| Commit | Description |
|--------|-------------|
| `381fd2d` | AutoPickAssets.Initialize + AutoPickTrigger ISystemInfo injection |
| `49c7554` | ReloadAssets ordering fix + explicit ISystemInfo in LoadAssetImage |
| `60892cd` | AddTrigger duplicate Initialize fix + shim LoadAssetImage scaling |
| `7909195` | Remove unused AddTrigger configProvider + cleanup Enabled fix |
| `4b9f761` | Core shim AddTrigger integration test + resize doc + shim boundary |

### Verification

| Gate | Result |
|------|--------|
| Core Verification | 90/90 |
| adapter-gate | Not triggered (no adapter file changes — expected) |
| Full WPF build | Not run (manual only) |

### What B8.2 achieves

| Boundary | Status |
|----------|--------|
| AutoPickAssets.Initialize(ISystemInfo, provider) sole entry point | ✅ |
| AutoPickTrigger ISystemInfo required — OnCapture uses _systemInfo | ✅ |
| Windows chain: ReloadAssets → Initialize → LoadInitialTriggers | ✅ |
| All 6 LoadAssetImage calls pass explicit ISystemInfo | ✅ |
| AddTrigger does not duplicate Initialize (Windows + Core shim) | ✅ |
| Shim LoadAssetImage fallback resize (intentional diff from Windows) | ✅ |
| MacAutoPickComposition explicit ISystemInfo param | ✅ |
| AddTrigger unused configProvider removed | ✅ |
| Core Verification 90/90 | ✅ |

### What B8.2 does NOT cover (B8.3+)

| Gap | Phase |
|-----|-------|
| AutoPickConfig runtime reads in OnCapture (`config` at line 216) | B8.3 |
| OCR/Yap static gateways | B9 |
| Input backend (IInputBackend injection) | B8.1 done |
| Shim deletion | B10 |
| Full WPF build restoration | Phase C |

### Notes

- B8.2 Core shim `GameTaskManager.AddTrigger` test **only tests the Core shim implementation**, not the Windows production `GameTaskManager.AddTrigger`. The shim and Windows are separate compile units; Windows correctness relies on source diff review.
- Core shim `GameTaskManager` is intentionally narrow (AutoPick only). Do not expand it — extract shared logic instead when macOS runtime needs full dispatcher behavior.
