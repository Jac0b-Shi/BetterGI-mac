# Real Window Verification — commit `5deddcd` Spike

## Scope

This document records what was verified during the real-window full-stack spike around commit `5deddcd65a2542d281f957f4ed5e5c02d1d5311b`.

This is not a release certification. It is a factual verification log.

## Environment

| Item | Value |
|---|---|
| macOS version | 26.5.1 |
| Machine | arm64 |
| YAAGL version | Unknown — fill in |
| Game | Genshin Impact |
| Game window mode | Wine window via YAAGL |
| Game resolution | 960 × 572 captured window |
| Retina scale | 1.0 on main display |
| Capture backend | Quartz `CGWindowListCreateImage` |
| HUD enabled | Unknown |
| dryRun | true (default) |
| realInputEnabled | false (default) |
| allowRuntimeRealInput | false (by default) |

## Verified Against Real Game Window

| Check | Result | Evidence / Notes |
|---|---|---|
| Window enumeration finds YAAGL/Genshin | Verified | `wine — 原神` id 7227 frame 18,82,960,572; YAAGL launcher id 7211 frame 320,89,1280,730 |
| SCK captures selected window | Unknown | |
| Quartz fallback used | Verified | Captured `/tmp/bettergi-mac-genshin-window.png`, 960×572, bytesPerRow 3840 |
| Real game window priority beats YAAGL launcher | Verified | `wine — 原神` priority 100; YAAGL launcher priority 0 |
| AutoPick F.png template matches real game UI | Unknown | |
| AutoPick blockers L/settings/chat work | Unknown | |
| AutoSkip OptionIcon template matches real game UI | Verified on Katheryne option frame | `/tmp/bettergi-mac-katheryne-current-builtin-options.png` and `/tmp/bettergi-mac-current-dialogue-check.png` matched `OptionIconRo`, `DailyRewardIconRo`, and `ExploreIconRo` |
| Multiple dialogue option observations produced | Real frame verified | Swift/Rust template reports emitted `DailyRewardIconRo`, `ExploreIconRo`, `OptionIconRo`, and `ChatPickRo` on the Katheryne option frame |
| Rust AutoPick returns decision | Unknown | |
| Rust AutoSkip returns decision | Verified on dialogue frame | Current `wine — 原神` window id 7345, 960×572. On Katheryne mid-dialogue, dry-run decision was `Space`, matching upstream `QuicklySkipConversationsEnabled` behavior. Latest screenshot saved to `/tmp/bettergi-mac-katheryne-current-target-resolver.png` |
| targetObservationIndex maps to intended option | Unit + real dry-run verified | `RustCoreBridgeAutoSkipDecisionTests` verifies synthetic mapping; Katheryne option frame selected `AutoSkip.DailyRewardIconRo-1` |
| normalizedRect → screen point clicks correct target | Unit + real dry-run verified | `InputTargetResolverTests` verifies coordinate math; Katheryne option frame produced dry-run click point `(677, 483)` for daily reward |
| PaddleOCR initializes ONNX Runtime | Verified by unit test | test_pp_ocr.png recognition passes |
| PaddleOCR Det outputs boxes on real game frame | Unknown | |
| PaddleOCR Rec reads Chinese text from real game frame | Verified on dialogue frame | Full-frame OCR read Katheryne/dialogue text from the real window |
| ColorRangeAndOcr mask works on real game frame | Unknown | |
| Runtime remained dry-run | Observed in Codex session log | |
| Any misfire observed | Unknown | |
| CPU/tick cost acceptable | Unknown | |

## Verified By Unit Tests / Test Assets

| Check | Result | Evidence |
|---|---|---|
| PaddleOCR Rec-only recognizes test_pp_ocr_number.png | Passed | Unit test |
| PaddleOCR Det+Rec recognizes test_pp_ocr.png key text | Passed | Unit test |
| ColorRangeAndOcr white mask positive case | Passed | Unit test |
| ColorRangeAndOcr empty green mask negative case | Passed | Unit test |
| AutoPick Rust tests (all scenarios) | Passed | cargo test |
| AutoSkip Rust target option index tests | Passed | cargo test |
| Rust dylib loaded (libmacgi_core.dylib) | CI/unit verified | nm -gU symbol check |
| Rust template matcher used by Swift bridge | Unit verified | TemplateMatchingRecognitionEngine |
| AutoSkip.OptionIconRo multi-match (maxMatchCount=8) | Synthetic verified | Unit test |
| AutoSkip DailyReward/Explore option priority | Real dry-run verified | Rust AutoSkip prioritizes `DailyRewardIconRo` / `ExploreIconRo` and matching option text before generic option selection; current real option frame selected `AutoSkip.DailyRewardIconRo-1` and mapped dry-run click point `(677, 483)` |
| PixelTemplateMatcher: CCorrNormed/CCoeffNormed/SqDiff | Passed | cargo test pixel_template |
| FFI match_template boundary (null/len/capacity) | Passed | cargo test ffi
| AutoSkip First/Last/Random/None | Passed | cargo test |
| C header syntax check | Passed | `clang -fsyntax-only -include shared/macgi_core.h -x c /dev/null` |
| swift build | Passed | Covered by `swift test` build |
| swift test | Passed | 29 Swift Testing tests |
| Swift Template `FindMulti` interim | Passed | `Template matcher emits multiple option icon observations when requested` |
| Rust PixelTemplateMatcher | Passed | BGRA frame + PNG template tests cover single, multi, maxMatchCount, ROI |
| Swift → Rust template FFI | Passed | `RustCoreBridge calls macgi_core_match_template for multi-template observations` |
| BetterGI `AssetScale` template resizing | Passed | Swift fallback and Rust FFI now resize 1920×1080 templates by `min(1, frameWidth / 1920)` before matching |
| Swift AutoSkip target click mapping | Passed | `RustCoreBridgeAutoSkipDecisionTests` + `InputTargetResolverTests` |
| cargo fmt --check | Passed | run from `macgi-core/` |
| cargo test | Passed | run from `macgi-core/`; 97 tests (85 unit + 12 integration) |

## Known Gaps

- No committed remote CI result yet.
- PaddleOCR Det postprocess uses connected-components interim path, not full OpenCV MinAreaRect rotated contour path.
- Real game dialogue option frame: recorded at `/tmp/bettergi-mac-katheryne-current-builtin-options.png`.
- Real target option click dispatch remains unverified; dry-run target selection and screen-point mapping are covered, but no CGEvent click was sent.
- Real Katheryne mid-dialogue frame: verified dry-run `Space`; real input remains disabled.
- Current mid-dialogue frame still reports `DisabledUiButtonRo`/`SubmitGoodsRo` template hits. They did not change the dry-run action because the Rust AutoSkip talk branch returns `Space`, while submit-goods cleanup only runs after the playing state disappears.
- Real runtime input: disabled / dry-run only (allowRuntimeRealInput = false).
- PixelTemplateMatcher: Rust baseline, not final OpenCV MatchTemplateHelper equivalent.
- Swift fallback matcher: debug/interim, ROI behavior may differ from Rust strict ROI.
- Real runtime input must remain disabled until foreground guard and allowRuntimeRealInput are confirmed.
- MacGIFrame data_len ABI hardening added post-spike (stabilization phase).

## Next Verification Steps

1. Verify SCK path against the same `wine — 原神` window, not only Quartz fallback.
2. Save ROI crops for minimap, HP bar, UID, and party list outside repository.
3. Verify AutoPick F icon match on real frame.
4. Verify AutoSkip multiple option observations on real frame.
5. Verify targetObservationIndex selects same option Swift clicks.
6. Verify dry-run logs before enabling any real input.
