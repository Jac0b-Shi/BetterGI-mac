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

**Inject existing `ISystemInfo` directly (Option A).**

Rationale:
- AutoPick uses exactly one member (`AssetScale`) and one derived property (`CaptureRect` via `ScaleMax1080PCaptureRect`)
- ISystemInfo is already the canonical source for AssetScale on both platforms
- Creating a narrower interface adds abstraction overhead with no practical benefit for a single double
- The interface is already in the shared namespace (via `Link` + native inclusion)

**The harder problem is AutoPickAssets:** it's a singleton with `AssetScale` consumed at construction time via `BaseAssets<T>(systemInfo)`. The `BaseAssets<T>` default constructor calls `TaskContext.Instance().SystemInfo`. To break this, `AutoPickAssets` constructor would need to receive `ISystemInfo` from the caller. But it's a singleton accessed via `AutoPickAssets.Instance`. This already has a `Configure(IAutoPickConfigProvider)` pattern from B6. A similar `ConfigureSystemInfo` or passing `ISystemInfo` into `Configure` is needed.

---

## 4. Construction Points for ISystemInfo Injection

### 4.1 Windows production callers

| Caller | Current SystemInfo source | Change needed |
|--------|--------------------------|---------------|
| `TaskTriggerDispatcher.Start()` → `GameTaskManager.LoadInitialTriggers(inputBackend)` → `new AutoPickTrigger(...)` | `TaskContext.Instance().SystemInfo` | Dispatcher already has `_inputBackend`; add `_systemInfo` (from `TaskContext.Instance()`). Pass to LoadInitialTriggers. |
| `GameTaskManager.LoadInitialTriggers(IInputBackend)` → `new AutoPickTrigger(...)` | Via `AutoPickTrigger.OnCapture` at runtime | Accept `ISystemInfo` param; pass to trigger constructor |
| `GameTaskManager.AddTrigger(name, config, inputBackend)` → `new AutoPickTrigger(...)` | Same | Same |
| `AutoPickAssets` singleton constructor (via `BaseAssets`) | `TaskContext.Instance().SystemInfo` | Pass ISystemInfo to AutoPickAssets.Configure() or new ctor param |
| `AutoPickAssets` template ROIs | via `systemInfo.AssetScale` | No change — systemInfo is already available via current pattern |

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

### 5.2 AutoPickAssets

Extend existing `Configure(IAutoPickConfigProvider)` to also accept `ISystemInfo`, OR create a new Configure overload that accepts both.

Since `BaseAssets<T>` stores `systemInfo` as a protected readonly field but `AutoPickAssets`'s template-only constructor runs at singleton creation (before Configure), the singleton constructor must either:
- Receive ISystemInfo at construction (via non-default BaseAssets ctor)
- Or defer all ROI calculations to Configure() (major refactor)

**Least-invasive approach:** make `BaseAssets<T>`'s default constructor use the injected ISystemInfo from a new `SetSystemInfo(ISystemInfo)` method, or accept it via `Configure()` on AutoPickAssets.

### 5.3 Windows chain changes

- `TaskTriggerDispatcher` receives `ISystemInfo` (alongside `IAutoPickConfigProvider` + `IInputBackend`)
- Forwards to `GameTaskManager.LoadInitialTriggers(IInputBackend, ISystemInfo)`
- Which forwards to `new AutoPickTrigger(..., systemInfo)`
- `AutoPickAssets.Configure(configProvider)` can also accept systemInfo, or it can be set before Configure

### 5.4 macOS composition

- `MacAutoPickComposition.Compose()` receives `ISystemInfo` from the host
- Passes to trigger constructor
- Configures AutoPickAssets with both `IAutoPickConfigProvider` and `ISystemInfo`

---

## 6. Minimum Scope for B8.2

| Change | Required | Files |
|--------|----------|-------|
| AutoPickTrigger adds ISystemInfo param | Required | `AutoPickTrigger.cs` |
| OnCapture uses `_systemInfo.AssetScale` instead of `TaskContext.Instance()` | Required | `AutoPickTrigger.cs` |
| GameTaskManager.LoadInitialTriggers/AddTrigger accept ISystemInfo | Required | `GameTaskManager.cs` |
| TaskTriggerDispatcher forwards ISystemInfo | Required | `TaskTriggerDispatcher.cs` |
| MacAutoPickComposition.Compose accepts ISystemInfo | Required | `MacAutoPickComposition.cs` |
| AutoPickAssets receives ISystemInfo during Configure or ctor | Required | `AutoPickAssets.cs`, `BaseAssets.cs` |
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

## 8. Fix B8.1 Commit Chain in Docs

**Current (wrong/duplicated line):**
```
3e25a80 + fc5ff09 + c7d4d61 + 3e25a80
```

**Correct series:**
- `e6c3495` — B8.1.0: Win32InputBackend
- `0b93346` — B8.1.0a: helper layering fix
- `7777b26` — B8.1.0b: WheelDelta cleanup
- `698efff` — B8.1.0c: import fix + adapter-gate
- `fc5ff09` — B8.1.0: csproj duplicate fix
- `c7d4d61` — B8.1.0: verification using fix
- `3e25a80` — B8.1.0: Exe→Library fix
- `47e36c7` — B8.1.1: AutoPick IInputBackend injection

**Or simplified range:**
- B8.1.0 series: `e6c3495` through `3e25a80` (adapter + gate)
- B8.1.1: `47e36c7` (trigger injection)
