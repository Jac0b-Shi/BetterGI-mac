# BetterGI Wine Integration

This directory contains the reproducible inputs and small integration components
needed to experiment with BetterGI input inside the Wine runtime used by YAAgl.
It does not contain a Wine source tree or a patched Wine binary.

## Scope

The work is intentionally split into two stages:

1. Run a Win32 input bridge in the same Wine prefix while the game is the macOS
   foreground application.
2. After the bridge behavior is proven, patch the matching `winemac.drv` source
   to support an explicitly registered virtual foreground window.

Stage one must not claim background input support. The production default in
betterGI-mac remains `foregroundCGEvent`. The launch page exposes the
experimental Wine Bridge backend while the runtime is stopped, persists the
selection, and still allows a command-line override for development.

## Locked Engine

The inspected YAAgl installation selects:

- Distribution: `11.0-1-crossover-signed-experimental`
- Display name: `Wine 11.0-1 Crossover (signed, experimental)`
- Runtime version: `wine-11.0`
- Runtime architecture: `x86_64`
- Launcher: `wine/bin/wine`
- Unix macOS driver: `wine/lib/wine/x86_64-unix/winemac.so`

There is no `wine/bin/wine64` or `wine/bin/wine-preloader` in this distribution.
Code must detect the executable and must not assume either path exists.

The GitHub Release asset SHA-256 and the inspected installation manifest are
recorded in [engine-lock.json](engine-lock.json). The audit evidence and
reproducibility limits are documented in
[Docs/wine-engine-provenance.md](../Docs/wine-engine-provenance.md). Local
absolute paths, game installation paths, credentials, signing identities and
session tokens are not stored.

## Reproducibility Status

The exact MacPorts overlay commit, CrossOver source baseline, ordered patch
series and build configuration are not currently published. See the provenance
audit for the evidence and the resulting macdrv patch boundary.

## Repository Boundary

- `bridge/`: native Windows x64 helper and protocol.
- `patches/`: `git format-patch` output from a separate matching Wine checkout.
- `scripts/`: engine verification, installation, signing and restore tooling.
- `engine-lock.json`: non-private engine identity and reproducibility status.

Complete Wine sources and locally extracted release assets must remain outside
this repository.

## Development Launch

The normal app packaging workflow builds the helper and includes it at:

```text
Contents/Resources/WineIntegration/BetterGIWineInputBridge.exe
```

Select `Wine Bridge（实验）` on the launch page while the runtime is stopped, or
launch the app bundle with an explicit command-line override:

```bash
open MacGI/.build/App/betterGI-mac.app --args \
  --input-backend wine-bridge \
  --wine-bridge-executable "$PWD/WineIntegration/bridge/build/BetterGIWineInputBridge.exe"
```

The current YAAgl OS Wine executable and prefix are detected from the standard
per-user data directory. Development overrides are available when needed:

```text
--wine-executable <path>
--wine-prefix <path>
--wine-target-executable <exe-name[,exe-name]>
```

Without an override, target discovery checks both `YuanShen.exe` (CN) and
`GenshinImpact.exe` (global).

Normal Wine Bridge use still requires the game to be the macOS foreground
application. Background delivery is enabled only by the validated combination:

```text
--wine-background-diagnostic
--wine-foreground-experiment mouse-prime
```

The dispatcher exposes this as a typed capability. `.none`, `.once` and
`.always` remain diagnostic strategies and cannot bypass the Swift or Core
foreground gates.

When validated background delivery is enabled, Swift configures the helper once
after target registration. Each real keyboard, mouse, wheel or text command
then runs `ensure_target_input_context()` and the original `SendInput` operation
consecutively on the same helper thread. The helper checks the registered game
HWND, submits at most three zero-delta priming events with a 150 ms delay, and
sends the original input immediately after the target becomes Wine foreground.
No synthetic `InputAction` is exposed to Core or task code, and there is no TCP
round trip between readiness confirmation and the original input.

`releaseAll` bypasses foreground diagnostics and priming. Swift sends it
directly whenever a bridge connection exists; disconnect and shutdown retain
the helper-side release fallback.

Real-game testing against the unmodified YAAgl Wine 11.0-1 engine showed that a
single priming event can leave `GetForegroundWindow()` on Wine's desktop HWND,
while finite three-attempt priming restores the registered game HWND reliably
enough for the tested background keyboard, mouse-button, relative-mouse and
movement sequence. The macOS foreground application remained unchanged during
that run. This confirms that recovery belongs in the Wine bridge input-delivery
boundary rather than in Core tasks or scripts.

The local scheduler group `Wine 后台输入诊断` retains an ordinary relative
mouse command before each input set as a comparison baseline:

```javascript
log.info(`[${label}] 零位移鼠标预热`);
moveMouseBy(0, 0);
await sleep(150);
```

Run that baseline with:

```bash
open MacGI/.build/App/betterGI-mac.app --args \
  --input-backend wine-bridge \
  --wine-background-diagnostic \
  --wine-foreground-experiment none \
  --wine-relative-mouse scaled
```

The same group also contains `Wine 后台输入诊断（无脚本预热）`, which omits
that action. A successful background run of the no-prime script is the
acceptance signal for bridge-private priming; it proves that task-level
`moveMouseBy(0, 0)` is not providing the recovery. The script-level variant is
retained only as an experimental comparison point. This branch still does not
patch Wine virtual foreground behavior, and background delivery remains behind
the explicit diagnostic launch mode until broader task validation is complete.
