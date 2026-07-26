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
betterGI-mac remains `foregroundCGEvent`; the bridge is enabled only by a
development command-line argument.

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

Build the helper with `scripts/verify-wine-bridge.sh`, package betterGI-mac
through the normal signed app workflow, then launch the app bundle with:

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

The bridge is not bundled into release artifacts during this experimental
stage. The game must remain the macOS foreground application; this branch does
not yet patch Wine virtual foreground behavior.
