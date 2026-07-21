#!/bin/zsh
set -euo pipefail

repo_root=${0:a:h:h}
cd "$repo_root"

fail() {
  print -u2 -- "Core extraction gate failed: $1"
  exit 1
}

[[ ! -d BetterGenshinImpact.Core/Shim ]] || fail "BetterGenshinImpact.Core/Shim must not exist"

if rg -n 'Unsupported.*AutoPickTextRecognizer|SKIPPED\s*[—-]|RecognitionTest|new TestTrigger\(' \
  BetterGenshinImpact.Core BetterGenshinImpact.Core.Host Test/BetterGenshinImpact.Core.Verification; then
  fail "placeholder, skipped verification, or fake AutoPick recognizer found"
fi

if rg -n 'Assets[\\/]+GameTask' BetterGenshinImpact.Core.Host MacGI/Sources/MacGI --glob '*.{cs,swift}'; then
  echo "Production code must load BetterGI assets from the canonical runtime GameTask root." >&2
  exit 1
fi

rg -q 'synchronizeBundledGameTaskResources\(\)' \
  MacGI/Sources/MacGI/Runtime/BetterGICoreProcessSupervisor.swift || {
  echo "Core supervisor must synchronize bundled GameTask resources before launch." >&2
  exit 1
}

if rg -n 'layout, gameTaskManagerPlatform\.SystemInfo' BetterGenshinImpact.Core.Host/Program.cs; then
  echo "Core Host must not query Swift window metrics before the callback channel attaches." >&2
  exit 1
fi

rg -q 'Core/Script/Dependence/Dispatcher.cs' BetterGenshinImpact.Core/BetterGenshinImpact.Core.csproj \
  || fail "shared upstream Dispatcher is not linked into Core"
rg -q 'AddHostObject\("dispatcher", new Dispatcher' \
  BetterGenshinImpact.Core.Host/Runtime/MacScriptProjectHostInitializer.cs \
  || fail "ClearScript dispatcher host is not registered"
real_user_verifier=Test/BetterGenshinImpact.RealUser.Verification/Program.cs
rg -q 'Test/BetterGenshinImpact.RealUser.Verification/\*\*' .github/workflows/mac-core.yml \
  || fail "macOS Core workflow does not run when the real User verifier changes"
rg -q 'VerifyProductionHostSurface\(javascriptProjects\)' "$real_user_verifier" \
  || fail "real User verification does not audit the production ClearScript host surface"
rg -q 'new MacScriptProjectHostInitializer\(\)\.Initialize' "$real_user_verifier" \
  || fail "real User host audit does not use the production macOS initializer"
rg -q 'Real User projects reference missing production host members' "$real_user_verifier" \
  || fail "real User host audit does not reject missing host members"
rg -q 'Real User genshin surface is not fully behavior-verified' "$real_user_verifier" \
  || fail "real User host audit does not reject unverified genshin members"
rg -q 'Real User dispatcher surface is not fully behavior-verified' "$real_user_verifier" \
  || fail "real User host audit does not reject unverified dispatcher members"
rg -q 'Production script host is missing canonical globals' "$real_user_verifier" \
  || fail "real User host audit does not reject missing canonical globals"
rg -q 'name is not \("AutoPick" or "AutoSkip"\)' "$real_user_verifier" \
  || fail "real User host audit does not reject uncomposed realtime triggers"
rg -q 'timerNames\.SetEquals\(\["AutoPick", "AutoSkip"\]\)' "$real_user_verifier" \
  || fail "real User host audit does not require the composed realtime trigger set"
for bv_type in BvPage BvLocator BvImage; do
  rg -q "AddHostType\(\"${bv_type}\", typeof\(${bv_type}\)\)" \
    BetterGenshinImpact.Core.Host/Runtime/MacScriptProjectHostInitializer.cs \
    || fail "ClearScript ${bv_type} host type is not registered"
  rg -q "Core/BgiVision/${bv_type}\.cs" BetterGenshinImpact.Core/BetterGenshinImpact.Core.csproj \
    || fail "upstream ${bv_type} source is not linked into Core"
done
if rg -n '\bTaskContext\b' BetterGenshinImpact/Core/BgiVision/BvLocator.cs; then
  fail "BvLocator must obtain capture metrics through BvRuntimePlatform"
fi
rg -q 'genshin\.getPositionFromMapWithMatchingMethod' \
  Test/BetterGenshinImpact.Core.Host.Verification/Program.cs \
  || fail "production ClearScript genshin map positioning is not behavior-verified"
rg -q 'genshin\.screenDpiScale' \
  Test/BetterGenshinImpact.Core.Host.Verification/Program.cs \
  || fail "production ClearScript genshin screen metrics are not behavior-verified"
rg -q 'genshin\.switchParty\("Team"\)' \
  Test/BetterGenshinImpact.Core.Host.Verification/Program.cs \
  || fail "production ClearScript genshin party switching is not behavior-verified"
rg -q 'await genshin\.tp' \
  Test/BetterGenshinImpact.Core.Host.Verification/Program.cs \
  || fail "production ClearScript genshin teleport is not behavior-verified"
rg -q 'genshin\.tpToStatueOfTheSeven' \
  Test/BetterGenshinImpact.Core.Host.Verification/Program.cs \
  || fail "production ClearScript statue teleport is not behavior-verified"
rg -Fq "genshin.goToCraftingBench('验证')" \
  Test/BetterGenshinImpact.Core.Host.Verification/Program.cs \
  || fail "production ClearScript crafting-bench path is not behavior-verified"
rg -q 'new GoToCraftingBenchTask\(\)\.GoToCraftingBench' \
  BetterGenshinImpact.Core.Host/Runtime/MacGenshinRuntimePlatform.cs \
  || fail "macOS genshin.GoToCraftingBench is not composed from the upstream task"
if rg -n '\b(TaskContext|Simulation\.SendInput|User32\.)\b' \
  BetterGenshinImpact/GameTask/Common/Job/GoToCraftingBenchTask.cs; then
  fail "shared GoToCraftingBenchTask still owns Windows runtime dependencies"
fi
rg -Fq "genshin.craftMaterial('测试材料', 0" \
  Test/BetterGenshinImpact.Core.Host.Verification/Program.cs \
  || fail "Core Host verification does not execute genshin.craftMaterial through ClearScript"
rg -q 'new CraftMaterialTask\(materialName, quantity, materialType\)\.Start' \
  BetterGenshinImpact.Core.Host/Runtime/MacGenshinRuntimePlatform.cs \
  || fail "macOS genshin.CraftMaterial is not composed from the upstream task"
if rg -n 'TaskContext|Simulation\.SendInput|VisionContext' \
  BetterGenshinImpact/GameTask/Common/Job/CraftMaterialTask.cs; then
  fail "shared CraftMaterialTask still owns Windows runtime dependencies"
fi
rg -q 'ForcedAvatarOcrFallbackCombatScenes' \
  Test/BetterGenshinImpact.Core.Host.Verification/Program.cs \
  || fail "Core Host verification does not force the upstream Avatar OCR fallback"
rg -q 'Real Avatar OCR fallback passed' \
  Test/BetterGenshinImpact.Core.Host.Verification/Program.cs \
  || fail "Core Host verification does not assert real Avatar OCR fallback completion"
for combat_end_source in AutoFightTask.cs AutoFightJsonTask.cs AutoFightSeek.cs; do
  rg -q 'AutoFightEndDetector\.IsFightFinished' \
    "BetterGenshinImpact/GameTask/AutoFight/${combat_end_source}" \
    || fail "${combat_end_source} does not use the shared C# combat-end detector"
done
rg -q '\("TXT", \(\) => txtFightTask\.CheckFightFinish\(0, 0\)\)' \
  Test/BetterGenshinImpact.Core.Verification/Program.cs \
  || fail "Core verification does not execute the upstream TXT combat-end flow"
rg -q '\("JSON", \(\) => jsonFightTask\.CheckFightFinish\(0, 0\)\)' \
  Test/BetterGenshinImpact.Core.Verification/Program.cs \
  || fail "Core verification does not execute the upstream JSON combat-end flow"
rg -q 'Action = ActionEnum\.Fight\.Code' \
  Test/BetterGenshinImpact.Core.Verification/Program.cs \
  || fail "Core PathExecutor verification does not contain a real fight waypoint"
rg -q 'PathExecutor Pathing executes the upstream AutoFightHandler task chain' \
  Test/BetterGenshinImpact.Core.Verification/Program.cs \
  || fail "Core verification does not execute fight through PathExecutor and AutoFightHandler"
rg -q 'fullPathExecutor\.SuccessFight == 1' \
  Test/BetterGenshinImpact.Core.Verification/Program.cs \
  || fail "Core verification does not require the fight waypoint to complete"
rg -q 'ActionFactory selects the upstream UpDownGrabLeafHandler' \
  Test/BetterGenshinImpact.Core.Verification/Program.cs \
  || fail "Core verification does not execute the shared four-leaf-sigil handler"
rg -q 'UpDownGrabLeafHandler recognizes the real SpaceKey template as flying' \
  Test/BetterGenshinImpact.Core.Verification/Program.cs \
  || fail "Core verification does not use upstream motion recognition after four-leaf interaction"
if rg -n 'AutoFightEndDetector|CheckFightFinish|BattleEndProgressBarColor' \
  MacGI/Sources; then
  fail "Swift owns a duplicate combat-end decision"
fi
rg -q 'JsonConvert\.DeserializeObject<GiTpPosition>' \
  BetterGenshinImpact.Core.Host/Runtime/MacTpTaskRuntimePlatform.cs \
  || fail "macOS TpTask composition does not restore the upstream runtime-only statue object"
for big_map_asset in Teyvat_0_256_SIFT.kp.bin Teyvat_0_256_SIFT.mat.png; do
  rg -q "Assets/Map/Teyvat/${big_map_asset}" \
    BetterGenshinImpact.Core/Manifest/model-artifacts.source-lock.json \
    || fail "production source-lock omits ${big_map_asset}"
done
rg -q 'new GameCaptureRegion' BetterGenshinImpact.Core.Host/Runtime/SharedCaptureRingReader.cs \
  || fail "capture ring frames do not retain the upstream clickable Region graph"
rg -q 'ColorConversionCodes\.BGRA2BGR' \
  BetterGenshinImpact/GameTask/Common/Map/MiniMap/MaskCalculator.cs \
  || fail "real BGRA capture frames are not normalized for upstream mini-map processing"
rg -q 'Microsoft.ClearScript.V8.Native.osx-arm64' BetterGenshinImpact.Core/BetterGenshinImpact.Core.csproj \
  BetterGenshinImpact.Core.Host/BetterGenshinImpact.Core.Host.csproj \
  || fail "native macOS arm64 ClearScript dependency is missing"
rg -q 'AttachRuntimeArtifactInitializer' BetterGenshinImpact.Core.Host/Program.cs \
  || fail "published Core Host does not provision locked runtime artifacts"
rg -q 'EnsureInstalledAsync' BetterGenshinImpact.Core.Host/Runtime/RuntimeArtifactProvisioner.cs \
  || fail "Core runtime artifact provisioner is not source-lock backed"
rg -Fq '| Live game execution | partial / blocked on explicit input authorization |' Docs/core-extraction-map.md \
  && rg -q 'overall first-step status remains \*\*partial\*\* until the four game-dependent projects complete' Docs/core-extraction-map.md \
  || fail "completion map must retain the explicit-input live-game Gate"

if rg -n 'BGIJSScriptRuntime|BGIScriptGroupScheduler' MacGI/Sources/MacGI MacGI/Package.swift; then
  fail "Swift owns BetterGI script execution or scheduling again"
fi

if rg -n '\bBGIScriptGroup(Project|Config)?\b|getScriptGroup\(|saveScriptGroup\(' \
  MacGI/Sources/MacGI/App MacGI/Sources/MacGI/Views \
  MacGI/Sources/MacGI/Runtime/BetterGICoreRPCClient.swift \
  MacGI/Sources/MacGI/Runtime/BetterGICoreProcessSupervisor.swift; then
  fail "Swift interprets or persists the upstream ScriptGroup document instead of consuming Core DTOs"
fi

if rg -n 'manifestJSON|JSONSerialization.*manifest' MacGI/Sources/MacGI; then
  fail "Swift parses BetterGI script manifests instead of consuming Core display DTOs"
fi

if rg -n 'coreTriggerNames|id:\s*"auto-(pickup|dialog|heal)' MacGI/Sources/MacGI/App; then
  fail "Swift hard-codes a parallel trigger catalog instead of consuming trigger.list DTOs"
fi

if rg -n '仍为 Mock|Mock UI|Mock Capture' MacGI/Sources/MacGI/Views; then
  fail "production UI exposes a fake runnable control"
fi

if rg -n 'BGIToggleMock|exportLogsMock|saveDebugFrameMock|Mock debug frame|Export logs requested \(mock\)' \
  MacGI/Sources/MacGI; then
  fail "production Swift source contains a deceptive mock action"
fi

if rg -n -i '\b(mock|fake)\b' MacGI/Sources/MacGI; then
  fail "production Swift source contains mock or fake platform state"
fi

if rg -n -U 'Button\s*(?:\([^)]*\))?\s*\{\s*\}' MacGI/Sources/MacGI/Views; then
  fail "production Swift UI contains a clickable action with an empty implementation"
fi

if rg -n '当前阶段只写入 Action Log|Test Actions' MacGI/Sources/MacGI/Views; then
  fail "production Swift UI contains an input action that only writes a log"
fi

rg -q 'Core input callback rejects a platform dispatch failure' \
  MacGI/Tests/MacGITests/BetterGICoreInputAcknowledgementTests.swift \
  || fail "Swift tests do not prove failed CGEvent dispatch is rejected back to Core"
rg -q 'return \.blocked\(reason: reason\)' MacGI/Sources/MacGI/App/AppState.swift \
  || fail "Swift input dispatch failures can still be acknowledged to Core"
rg -q 'Failed event clears the active task and exposes the Core error' \
  MacGI/Tests/MacGITests/BetterGICoreSchedulerEventTests.swift \
  || fail "Swift tests do not prove scheduler failed state reaches AppState"
rg -q 'Terminal event cannot be overwritten by a late run response' \
  MacGI/Tests/MacGITests/BetterGICoreSchedulerEventTests.swift \
  || fail "Swift tests do not cover the scheduler event/run response race"
rg -q 'Terminal event cannot be overwritten by late control responses' \
  MacGI/Tests/MacGITests/BetterGICoreSchedulerEventTests.swift \
  || fail "Swift tests do not cover scheduler event/control response races"
rg -q 'Text\(schedulerError\)' MacGI/Sources/MacGI/Views/Pages/WorkflowPages.swift \
  || fail "Swift scheduler UI does not expose the Core terminal error"
rg -q 'catch \(PlatformCallbackException\)' \
  BetterGenshinImpact.Core.Host/Transport/PlatformCallbackChannel.cs \
  || fail "Core detaches the callback channel after a platform business rejection"
rg -q 'A platform business rejection detached the reusable callback channel' \
  Test/BetterGenshinImpact.Core.Host.Verification/Program.cs \
  || fail "Core Host verification does not prove callback recovery after input rejection"
rg -q 'scheduler did not publish failed after a platform input rejection' \
  Test/BetterGenshinImpact.Core.Host.Verification/Program.cs \
  || fail "Core Host verification does not propagate platform rejection to scheduler failed"
rg -q 'RethrowUnexpectedExceptions => true' \
  BetterGenshinImpact.Core.Host/Runtime/MacTaskRunnerPlatform.cs \
  || fail "macOS TaskRunner can swallow an exception and report scheduler completion"
rg -q 'ThrowOnLockFailure => true' \
  BetterGenshinImpact.Core.Host/Runtime/MacTaskRunnerPlatform.cs \
  || fail "macOS TaskRunner can report completion after task-lock rejection"
rg -q 'PropagateProjectExceptions => true' \
  BetterGenshinImpact.Core.Host/Runtime/MacScriptServicePlatform.cs \
  || fail "macOS ScriptService can swallow a project exception and report scheduler completion"
rg -q 'scheduler reported success or executed the project after task-lock rejection' \
  Test/BetterGenshinImpact.Core.Host.Verification/Program.cs \
  || fail "Core Host verification does not reject scheduler task-lock contention"

if rg -n 'AutoSkipConfig Config|AutoSkipRuntimePlatform\.Current\.Config' \
  BetterGenshinImpact/GameTask/AutoSkip \
  BetterGenshinImpact/Core/Runtime/Windows/WindowsAutoSkipRuntimePlatform.cs \
  BetterGenshinImpact.Core.Host/Runtime/MacAutoSkipRuntimePlatform.cs; then
  fail "AutoSkip runtime platform owns Core business configuration"
fi
rg -q 'ClickChatOption = "优先选择最后一个选项"' \
  BetterGenshinImpact/GameTask/AutoPathing/PathExecutorAutoSkipPlatform.cs \
  || fail "PathExecutor AutoSkip policy is not owned by the shared Core factory"
if rg -n 'class (Mac|Windows)PathExecutorAutoSkipPlatform' \
  BetterGenshinImpact BetterGenshinImpact.Core.Host; then
  fail "PathExecutor AutoSkip policy is duplicated by platform adapters"
fi
if rg -n 'PathExecutorPlatform\.Current|PathExecutorAutoSkipPlatform\.Current|ScriptGroupExecutionServices\.Current' \
  BetterGenshinImpact/GameTask/AutoPathing/PathExecutor.cs; then
  fail "PathExecutor still resolves process-global services during execution"
fi
rg -q 'mac-core-extraction' .github/workflows/wpf-build.yml \
  || fail "Windows WPF build does not gate mac-core-extraction pushes"
rg -q 'startupPollLimit = 4_800' MacGI/Sources/MacGI/Runtime/BetterGICoreProcessSupervisor.swift \
  && test "$(rg -c '0\.\.<Self\.startupPollLimit' MacGI/Sources/MacGI/Runtime/BetterGICoreProcessSupervisor.swift)" -eq 2 \
  || fail "Swift does not allow the Core Host a bounded 120-second native cold-start window"
rg -q '#if DEBUG' MacGI/Sources/MacGI/Runtime/BetterGICoreProcessSupervisor.swift \
  && rg -q 'resolveDevelopmentExecutableURL' MacGI/Sources/MacGI/Runtime/BetterGICoreProcessSupervisor.swift \
  || fail "SwiftPM Debug builds cannot locate the staged BetterGI Core Helper"
rg -q 'appState\.startRuntime\(\)' MacGI/Sources/MacGI/Views/Pages/OverviewPage.swift \
  || fail "The global runtime button does not start the Core runtime"
if rg -n 'runSchedulerGroups\(\)|toggleStartPause\(\)' MacGI/Sources/MacGI/Views/Pages/OverviewPage.swift; then
  fail "The global runtime button still starts the scheduler"
fi
if rg -n 'guard lastCapturedFrame != nil else \{ return max\(' MacGI/Sources/MacGI/App/AppState.swift; then
  fail "Swift reports a synthetic capture FPS before receiving a real frame"
fi
if rg -n 'continue-on-error:[[:space:]]*true' .github/workflows/wpf-build.yml; then
  fail "Windows WPF build is configured as a soft failure"
fi
rg -q 'one failing macOS trigger stopped later triggers from processing the same frame' \
  Test/BetterGenshinImpact.Core.Host.Verification/Program.cs \
  || fail "macOS trigger dispatcher does not verify per-trigger exception isolation"
rg -q 'macOS trigger dispatcher did not restart after a prior loop failure' \
  Test/BetterGenshinImpact.Core.Host.Verification/Program.cs \
  || fail "macOS trigger dispatcher does not verify restart after loop failure"

if rg -n '由 Rust/OpenCV 提供|Rust.*(脚本|调度|路径|识别)' MacGI/Sources/MacGI; then
  fail "Swift UI assigns BetterGI business authority to Rust"
fi

if rg -n 'TemplateMatchingRecognitionEngine|PaddleOCRRecognitionEngine|BGIYOLOOnnxRuntime|BGIMiniMapLocalizationService|BGIBigMapInteractionService|BGIAuto[A-Za-z]+Service|BGIScriptRepositoryUpdater|TaskTriggerLoopController' \
  MacGI/Sources/MacGI; then
  fail "historical Swift BetterGI business translation still exists in the App source tree"
fi

if rg -n 'onnxruntime-swift|OnnxRuntimeBindings' MacGI/Package.swift MacGI/Sources/MacGI; then
  fail "Swift still links an inference runtime owned by C# Core"
fi

if rg -n 'TemplateMatchingRecognitionEngine|PaddleOCRRecognitionEngine|BGIOnnx' \
  MacGI/Sources/MacGI/App MacGI/Sources/MacGI/Views; then
  fail "Swift UI owns recognition business state instead of consuming Core DTOs"
fi

git diff --check
print -- "Core extraction static gate passed."
