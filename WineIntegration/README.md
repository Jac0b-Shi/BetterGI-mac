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

Select `Wine Bridge` on the launch page while the runtime is stopped, or
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

Wine Bridge is the default input backend. CGEvent remains available as the
compatibility backend for cloud gaming, remote clients and other non-Wine
targets. Existing explicit user selections remain persisted.

Wine Bridge uses the validated `mouse-prime` background-delivery policy by
default. The following arguments remain available for diagnostics and
historical comparisons:

```text
--wine-background-diagnostic
--wine-foreground-experiment mouse-prime
```

The dispatcher exposes `mouse-prime` as a typed background capability. `.none`,
`.once` and `.always` remain diagnostic strategies and cannot bypass the Swift
or Core foreground gates.

When validated background delivery is enabled, Swift configures the helper once
after target registration. Each real keyboard, mouse, wheel or text command
checks the registered game HWND in the helper. If Wine foreground differs, the
helper starts a monotonic 3-second wake state and returns a pending status
without executing the original action. Swift retries that same business
command with adaptive delays of 20, 40, 80, 120 and then 200 ms. The helper
sends a zero-delta relative mouse prime on the first request. As soon as
`GetForegroundWindow()` equals the registered target
HWND, that same retried business command immediately executes its real input;
there is no separate ready-query/input window. Because real-game testing proved
Wine can consume input while still reporting its desktop HWND, the helper also
adds one private complete left-button click on the next request through the normal
`send_mouse_button()` down/up path. This is deliberately experimental: the
tested cold-focus path swallowed the complete click and delivered the following
F6 without a visible extra attack. An unexpected early recovery could still
make the probe visible as one attack. Before emitting the click, the helper
requires `GetCursorPos()` to fall inside the registered target client rectangle
and requires `WindowFromPoint()` to resolve to that target root window. A title
bar, resize border, another Wine window or an indeterminate hit is never clicked.
The command remains pending and eventually fails instead of entering best-effort
delivery when this safety check cannot be satisfied. After a 500 ms settle
window, a retry
enters the best-effort ready state and executes the original
input exactly once and ACKs only when that real `SendInput` succeeds. The ready
state is cached for the current registered Bridge target and is invalidated
when macOS activates the game and then another host application. No failure
falls back to CGEvent, and no synthetic `InputAction` is exposed to Core or
task code.

`releaseAll` bypasses foreground diagnostics and priming. Swift sends it
directly whenever a bridge connection exists; disconnect and shutdown retain
the helper-side release fallback.

Real-game testing against the unmodified YAAgl Wine 11.0-1 engine showed that
blocking inside one helper request for 15 seconds never advances Wine
foreground state. Wine must regain its event loop between priming attempts.
The stateful protocol preserves atomicity at the important boundary: the
successful foreground check and real input still happen in one helper request.
The helper logs wake elapsed time, prime count, first-prime `SendInput` result
and initial/final Wine foreground HWND so idle-duration tests can establish the
eventual production deadline.

### Confirmed wake-path results

The shared property of every successful background-input test so far is not
the foreground query itself. The priming request must return to Wine before the
real input is attempted:

| Path | Result | Finding |
| --- | --- | --- |
| Task `moveMouseBy(0, 0)` -> sleep -> real input | PASS | Returning through the task/bridge boundary gives Wine time to process the prime. |
| Bridge prime RPC -> sleep/query RPC -> retry original command | PASS | The no-script-prime scheduler test confirms priming can remain private to the bridge. |
| Prime -> poll for 15 seconds inside one helper command | FAIL | Wine foreground stayed on its desktop HWND for the full deadline. |
| Cross-request prime -> require target HWND for 15 seconds | FAIL | Returning to Wine's event loop was not sufficient; target foreground is not a reliable delivery gate. |
| Five mouse primes -> 2-second settle -> cache ready | PARTIAL | The task ran, but its first F6 and text input were swallowed; the third left click was the first visible game input. |
| Mouse primes + F24/XBUTTON2 probes -> 5-second settle | PARTIAL | Waiting longer and exercising unrelated input paths still swallowed the first two real inputs. |
| Mouse primes + `0` key probes -> 5-second settle | FAIL | Reusing the normal key path still left the first two attacks swallowed. |
| Mouse primes + left-button release probes -> 5-second settle | FAIL | F6 and the first complete business click were still swallowed; the second complete click attacked. |
| Mouse prime + one complete left-click probe -> 500 ms settle | PASS | F6 and the following click were delivered on their first attempts without a visible extra input. |
| `SetForegroundWindow(target)` diagnostic | Rejected for production | It can introduce host-focus side effects and is not required by the successful path. |

The query RPC is useful for diagnostics, but it has not been proven to cause
the wake-up. The minimum confirmed sequence is:

```text
prime SendInput
-> return from the helper request
-> allow Wine to process its event loop
-> bounded wait
-> retry the original input command
```

Foreground equality also cannot yet be treated as proof that delivery is
possible or impossible. A successful F6/text/click run was logged while the
post-input diagnostic still reported Wine desktop `0x10020` instead of target
`0x30054`. The current experimental backend therefore uses foreground equality
as an early-ready signal, then falls back to one real-input attempt after a
bounded cross-request probe sequence. F24 and XBUTTON2 did not prevent the first
two business inputs from being swallowed. Replacing those probes with the
ordinary `0` key path or release-only left-button events also failed. The
current experiment therefore uses one complete private left click, because the
first complete click was swallowed and the following click was the first
visible attack. The private-click variant subsequently delivered F6 on its first
attempt without a visible extra input. Until the Wine/macdrv path is understood,
the target-HWND check remains diagnostic rather than a complete delivery oracle.
An observed host-window full-screen transition proved that an unqualified click
can hit Wine window chrome, so client-area hit validation is a required safety
boundary rather than an optional diagnostic.

Wine Bridge text delivery currently follows upstream Windows semantics by
submitting `KEYEVENTF_UNICODE` key-down/key-up pairs. The helper ACK confirms
that Wine accepted `SendInput`, not that a game text field consumed the text.
Background entry of the Thousand Star stage name therefore remains unverified
and must not be treated as a supported background-text contract yet.

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
retained only as an experimental comparison point. This branch does not patch
Wine virtual foreground behavior. The validated Bridge-private wake policy is
the normal Wine Bridge default; diagnostic launch arguments remain available
for reproducing rejected alternatives.
