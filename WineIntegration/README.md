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

The game must remain the macOS foreground application during normal use. The
explicit `--wine-background-diagnostic` launch mode exists only to measure
unmodified Wine behavior and does not claim supported background automation.
The `--wine-foreground-experiment mouse-prime` diagnostic strategy invokes the
bridge-private `prepareTargetInput` command only when Wine's foreground HWND
differs from the registered game HWND. The bridge performs Wine input-context
priming internally and waits up to 150 ms for Wine to restore the target before
Swift delivers the original input. The bridge keeps checking and event
submission separate: `prepareTargetInput` reports whether priming is required,
`primeTargetInput` submits the event and returns immediately, and a separate
read-only foreground query checks readiness after 150 ms. No synthetic
`InputAction` is exposed to Core or task code.

On the tested unmodified YAAgl Wine 11.0-1 engine, the private priming commands
still leave `GetForegroundWindow()` on Wine's desktop HWND (`0x10020`) instead
of the registered game HWND (`0x30054`). The experiment therefore remains
diagnostic-only and must not be described as supported background automation.

The only successful background-input baseline so far uses an ordinary relative
mouse command from the local diagnostic script before each input set:

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

This script-level workaround has been observed to restore Wine's game
foreground without bringing Wine to the macOS foreground. It is retained only
as an experimental comparison point; production background support still
requires a reliable bridge or `winemac.drv` solution. This branch does not patch
Wine virtual foreground behavior.
