# betterGI-mac

betterGI-mac is the SwiftUI/AppKit frontend bundled with the extracted BetterGI C# Core in this repository.

Production script catalog, scheduling, ClearScript execution and BetterGI task decisions must come from `BetterGenshinImpact.Core.Host`. Swift owns the macOS UI, ScreenCaptureKit capture, guarded input dispatch and platform callbacks. If the Core Host is unavailable, running scripts is disabled; there is no JavaScriptCore, mock, or Rust business fallback.

The project is intended to be released under GPLv3, matching upstream BetterGI. Upstream BetterGI visual assets used by this prototype are listed in `NOTICE`.

The runtime root is `~/Library/Application Support/betterGI-mac/`. The app starts the bundled `Contents/Resources/BetterGICore/BetterGenshinImpact.Core.Host`, negotiates the versioned local RPC protocol, and obtains script groups and scheduler state from that process. The self-contained .NET publish tree lives under Resources so the outer App signature seals its managed assemblies as resources; `Contents/Helpers` is reserved for independently bundled nested code.

Build:

```bash
swift build
```

Publish the self-contained C# Core Host used by the app:

```bash
./scripts/package-bettergi-core.sh
```

Run:

```bash
swift run betterGI-mac
```

## Known limitations

- The mini-map marker overlay currently inherits the upstream BetterGI mini-map localization coverage. It works in supported regions such as Mondstadt and Liyue Harbor, but may show no markers in some newer map areas even when the game's mini-map shows nearby waypoints. This is an upstream localization-data/algorithm limitation shared with the Windows implementation, not a macOS HUD rendering failure. The full-map marker overlay is not affected.
