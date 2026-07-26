# YAAgl Wine Engine Provenance

## Audit Scope

This audit records the Wine runtime selected by the current YAAgl OS
installation before BetterGI adds an experimental Win32 input bridge. It does
not assert that Wine background input or a compatible `winemac.drv` patch
already exists.

The machine-readable values are locked in
[`WineIntegration/engine-lock.json`](../WineIntegration/engine-lock.json).
Private absolute paths, the game installation path, credentials, signing
identities and bridge session tokens are intentionally excluded.

## Selected Distribution

YAAgl stores the selected distribution as:

```text
11.0-1-crossover-signed-experimental
```

The latest YAAgl upstream source checked during the audit was commit
`ca78abc29c2fc236261d088c6907d28cab6e9476`. Its distribution catalog maps that
identifier to:

```text
Wine 11.0-1 Crossover (signed, experimental)
wine-crossover-11.0-1-osx64-signed.tar.xz
```

The GitHub Release API reports:

```text
size:   456021524 bytes
sha256: 89fa7e90fb626523a90d5867a03c6be785d017176739c6320a3b86c7838c3a35
```

The local runtime reports `wine-11.0`. Its installed content manifest contains
11,027 files after excluding `.DS_Store`; the sorted relative-path/file-digest
manifest hashes to:

```text
2bf39883b039e60d51fb848b8d61d67965e062140a272e6165eb5bd83ef2fc17
```

## Runtime Layout

The distribution uses an x86_64 Mach-O launcher:

```text
wine/bin/wine
wine/bin/wineserver
wine/lib/wine/x86_64-unix/wine
wine/lib/wine/x86_64-unix/winemac.so
wine/lib/wine/x86_64-unix/win32u.so
```

Its Windows mac driver modules are:

```text
wine/lib/wine/x86_64-windows/winemac.drv
wine/lib/wine/i386-windows/winemac.drv
```

This release does not contain `wine/bin/wine64` or
`wine/bin/wine-preloader`. BetterGI integration code must detect the launcher
instead of assuming either legacy path.

## Signing Result

The inspected Mach-O runtime files are ad-hoc signed:

```text
flags:          adhoc
authority:      none
TeamIdentifier: not set
entitlements:   none
```

The word `signed` in the distribution name therefore does not mean that these
files carry an Apple Development or Developer ID identity. Installation and
restore tooling must inspect the actual code signature and must not invent or
silently replace its identity.

## Reproducibility Gap

The asset repository names
[`riverfog7/macports-wine`](https://github.com/riverfog7/macports-wine) as its
source. The release notes also state that the binary contains:

- timeout patches for some games;
- CN game compatibility patches;
- Media Foundation patches;
- CrossOver patches on Wine 11.0.

The public metadata does not identify:

- the exact `riverfog7/macports-wine` commit;
- the exact CodeWeavers CrossOver source release or commit;
- the ordered patch series;
- the build configuration and signing script.

The installed binary is therefore not strictly reproducible from the currently
published metadata. Bridge development can proceed because it uses public
Win32 APIs inside the existing prefix. A `winemac.drv` patch cannot be claimed
compatible until its source and ABI baseline are identified.

## Stage Boundary

The first experimental stage is limited to:

```text
BetterGI-mac
    -> authenticated loopback protocol
    -> native Win32 helper in the current YAAgl prefix
    -> SendInput
```

The game must remain the macOS foreground application in this stage. Virtual
foreground behavior, DirectInput foreground acquisition and host cursor
decoupling belong to a later patch against the accurately matched Wine source.
