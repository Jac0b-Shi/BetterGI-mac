# B8.1 Audit: Input Send Extraction

**Status:** Audit only — no code changes
**Predecessor:** B7 complete (commit `0cf37a7`)

---

## 1. Input Call Sites in AutoPickTrigger.OnCapture()

All five call sites in `BetterGenshinImpact/GameTask/AutoPick/AutoPickTrigger.cs`:

| # | Line | Code | IInputBackend equivalent | Trigger condition |
|---|------|------|--------------------------|-------------------|
| 1 | 198 | `Simulation.SendInput.Mouse.VerticalScroll(2)` | `Scroll(2)` | Scroll-wheel icon detected; cycle through nearby items |
| 2 | 210 | `Simulation.SendInput.Keyboard.KeyPress(PickVk)` | `KeyPress(pickVk)` | `ForceInteraction == true` (script override) |
| 3 | 257 | `Simulation.SendInput.Keyboard.KeyPress(PickVk)` | `KeyPress(pickVk)` | No whitelist, no blacklist, no chat/settings icon |
| 4 | 355 | `Simulation.SendInput.Keyboard.KeyPress(PickVk)` | `KeyPress(pickVk)` | Whitelist match found |
| 5 | 386 | `Simulation.SendInput.Keyboard.KeyPress(PickVk)` | `KeyPress(pickVk)` | Passed all blacklist/fuzzy checks |

**Key observations:**
- Only two semantic IInputBackend operations needed: `KeyPress(BgiKey)` and `Scroll(int)`
- All four `KeyPress` sites use `AutoPickAssets.Instance.PickVk` (returns `BgiKey`)
- No mouse positioning, button down/up, or per-key-state operations in OnCapture
- `PickVk` is already a `BgiKey` — no key-code translation at call site

---

## 2. Current Platform Behavior

### Windows (WPF project)
- `Simulation.SendInput` = `Fischless.WindowsInput.InputSimulator` (raw Win32 `SendInput`)
- `Keyboard.KeyPress(VirtualKeyCode)` — maps `BgiKey` → `VirtualKeyCode` internally
- `Mouse.VerticalScroll(int)` = Win32 `mouse_event` with scroll delta

### macOS (Core project with `BGI_PLATFORM_MAC`)
- `Simulation.SendInput` = shim `SendInputFacade` → `PlatformServices.Input` (static `IInputBackend`)
- `Keyboard.KeyPress(BgiKey)` → `PlatformServices.Input.KeyPress(key)`
- `Mouse.VerticalScroll(int)` → `PlatformServices.Input.Scroll(clicks)`
- **Already routable through IInputBackend** but uses static gateway `PlatformServices.Input`

### Problem
On Core/macOS, input is technically going through `IInputBackend`, but via `PlatformServices.Input` — a static gateway. The shim facade hides this but does not eliminate it. B8.1 must inject `IInputBackend` as a constructor parameter so the trigger uses an explicit dependency, not `PlatformServices.Input`.

---

## 3. AutoPickTrigger Creation Paths

| # | File:line | Constructor | Context | Can inject IInputBackend? |
|---|-----------|-------------|---------|---------------------------|
| 1 | `GameTaskManager.cs:47` | `new AutoPickTrigger()` | Windows dispatcher init (no external config, no runtime state) | **Needs audit** — GameTaskManager would need to accept IInputBackend or access it via DI |
| 2 | `GameTaskManager.cs:97` | `new AutoPickTrigger(externalConfig)` | Windows script launch (external config from script) | Same as #1 |
| 3 | `MacAutoPickComposition.cs:52` | `new AutoPickTrigger(externalConfig, runtimeState, configProvider)` | macOS composition root | **Yes** — already passes multiple dependencies; adding IInputBackend is trivial |
| 4-10 | `Verification/Program.cs` (7 sites) | All overloads | Test harness | **Yes** — tests already create `RecordingInputBackend`; can pass it directly |

---

## 4. Migration Strategy

### Option A: Nullable fallback (one-step transition)

```csharp
private readonly IInputBackend? _inputBackend;

private IInputBackend Input =>
    _inputBackend ?? PlatformServices.Input;
```

Windows paths keep `_inputBackend = null` → fallback to `PlatformServices.Input`.
macOS path passes explicit backend.

**Pros:** Minimal Windows change, zero WPF compilation risk
**Cons:** Perpetuates static fallback; Windows never migrates

### Option B: Required injection (all callers explicit)

```csharp
private readonly IInputBackend _inputBackend; // non-nullable
```

All callers must supply IInputBackend:
- **macOS:** `MacAutoPickComposition` passes backend (trivial change)
- **Windows GameTaskManager:** receives IInputBackend via constructor or DI container
- **Verification tests:** already have `RecordingInputBackend`

**Pros:** Clean architecture; no static fallback anywhere
**Cons:** Touches Windows GameTaskManager and DI registration

### Recommendation: Option B

The injection chain is short and already exists for other dependencies (configProvider, runtimeState). Windows GameTaskManager is already within scope of Platform.Abstractions reference. Adding IInputBackend to the trigger constructor is the natural next step in the B7 pattern.

Additionally: the shim `SendInputFacade` exists in Core's `Shim/Simulation.cs`. Once AutoPickTrigger directly accesses `_inputBackend`, the `SendInputFacade.Keyboard.KeyPress` / `Mouse.VerticalScroll` methods become dead code for AutoPickTrigger. They are still needed for other consumers in Core but this migration paves the way.

---

## 5. Behavioral Differences

| Aspect | Win32 SendInput | IInputBackend (Core) | Notes |
|--------|----------------|----------------------|-------|
| Key press timing | Synchronous — blocks until driver accepts event | Platform-dependent (macOS: CGEventPost, synchronous) | No observable difference at AutoPick timescale |
| Scroll granularity | WHEEL_DELTA = 120 per notch; `VerticalScroll(2)` = 2 notches | `Scroll(2)` semantic: 2 scroll "clicks" | Backends must agree on scroll unit |
| Key state | Windows: true hardware emulation (system-wide) | macOS: CGEvent targets the frontmost app | AutoPick only sends to game window — consistent |

No known behavioral gap that would affect AutoPick correctness.

---

## 6. Migration Steps (B8.1 implementation plan)

| Step | Description | Impact |
|------|-------------|--------|
| 8.1.1 | Add `IInputBackend?` parameter to AutoPickTrigger master constructor | Non-breaking: nullable parameter with fallback |
| 8.1.2 | Replace 5 Simulation.SendInput calls with `Input.KeyPress/Scroll` | OnCapture uses `_inputBackend` property |
| 8.1.3 | Pass IInputBackend from MacAutoPickComposition | One-line change |
| 8.1.4 | Register IInputBackend in WPF DI, pass from GameTaskManager | Windows: add `IInputBackend` to constructor or DI resolution |
| 8.1.5 | Verification: B8.1 assertions (backend receives KeyPress + Scroll calls) | New test assertions |
| 8.1.6 | Remove dead SendInputFacade paths (optional — other Shim consumers) | Deferred to B10 |

**Do NOT:**
- Create `IAutoPickInput` or wrapper interfaces
- Change `IInputBackend` API
- Touch B8.2/B8.3/OCR/Yap
- Delete Shim files
