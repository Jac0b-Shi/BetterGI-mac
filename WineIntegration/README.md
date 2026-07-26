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
recorded in [engine-lock.json](engine-lock.json). Local absolute paths, game
installation paths, credentials, signing identities and session tokens are not
stored.

## Reproducibility Status

The release repository points to
[`riverfog7/macports-wine`](https://github.com/riverfog7/macports-wine), and the
release notes describe timeout, CN game, Media Foundation and CrossOver patches.
They do not identify the exact overlay commit, CrossOver source baseline,
ordered patch series or build configuration.

The current binary therefore cannot yet be reproduced exactly from public
metadata. A future `winemac.drv` patch must not be generated against Wine master
or described as compatible until those inputs are identified.

The distribution name says `signed`, but the inspected Mach-O files are ad-hoc
signed with no Team ID and no entitlements. Installation tooling must preserve
that fact instead of assuming an Apple Development or Developer ID signature.

## Repository Boundary

- `bridge/`: native Windows x64 helper and protocol.
- `patches/`: `git format-patch` output from a separate matching Wine checkout.
- `scripts/`: engine verification, installation, signing and restore tooling.
- `engine-lock.json`: non-private engine identity and reproducibility status.

Complete Wine sources and locally extracted release assets must remain outside
this repository.
