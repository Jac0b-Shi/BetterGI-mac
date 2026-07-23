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

[[ ! -e MacGI/Sources/MacGI/Resources/GameTask ]] \
  || fail "Swift source tree must not contain a second GameTask asset copy"
rg -q 'stage-game-task-assets\.sh' MacGI/scripts/package-macgi-app.sh \
  || fail "App packaging does not stage canonical BetterGI GameTask assets"
rg -q -- '--recognition-smoke --runtime-root' MacGI/scripts/package-macgi-app.sh \
  || fail "App packaging does not verify its staged recognition resources"
rg -qx 'AutoGeniusInvokation' MacGI/Resources/game-task-assets.manifest \
  || fail "composed AutoGeniusInvokation assets are missing from the canonical package manifest"

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
rg -q 'VerifyProductionHostSurface\(javascriptProjects, scriptGroupExecutionServices\)' "$real_user_verifier" \
  || fail "real User verification does not audit the production ClearScript host surface"
rg -q 'new MacScriptProjectHostInitializer\(scriptGroupExecutionServices\)\.Initialize' "$real_user_verifier" \
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
rg -Fq '| Live game execution | partial |' Docs/core-extraction-map.md \
  && rg -q 'overall first-step status remains \*\*partial\*\* until the four game-dependent projects complete' Docs/core-extraction-map.md \
  || fail "completion map must retain the real-game execution Gate"

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
if rg -n -U 'case "overlay\.command":.*?addLog\([^\n]*Core overlay.*?return \["acknowledged": true\]' \
  MacGI/Sources/MacGI/Runtime/BetterGICorePlatformAdapter.swift; then
  fail "Swift still acknowledges overlay commands without applying them"
fi
rg -q 'applyCoreOverlayCommand' MacGI/Sources/MacGI/Runtime/BetterGICorePlatformAdapter.swift \
  && rg -q 'store\.state\.allRectangles' MacGI/Sources/MacGI/Views/HUDView.swift \
  || fail "Core overlay commands are not rendered by the Swift HUD"
rg -q 'operation = "setMapPointData"' BetterGenshinImpact.Core.Host/Runtime/MacMapMaskRuntimePlatform.cs \
  && rg -q 'operation = "setMapViewport"' BetterGenshinImpact.Core.Host/Runtime/MacMapMaskRuntimePlatform.cs \
  && rg -q 'store\.state\.mapPoints' MacGI/Sources/MacGI/Views/HUDView.swift \
  && rg -q 'case "setMapPointData"' MacGI/Sources/MacGI/Model/CoreOverlayState.swift \
  && rg -q 'case "setMapViewport"' MacGI/Sources/MacGI/Model/CoreOverlayState.swift \
  || fail "MapMask point data and viewport updates are not independently connected to the Swift HUD"
if rg -n '@Published[^\n]*coreOverlay' MacGI/Sources/MacGI/App/AppState.swift; then
  fail "high-frequency Core overlay state must not invalidate the entire AppState UI tree"
fi
if rg -n -U 'operation = "setMapViewport".*?points\s*=' \
  BetterGenshinImpact.Core.Host/Runtime/MacMapMaskRuntimePlatform.cs; then
  fail "MapMask viewport updates must not resend the point collection"
fi
if rg -n -U 'recognitionOverlay\([^)]*\).*?EmptyView\(\)' MacGI/Sources/MacGI/Views/HUDView.swift; then
  fail "Recognition overlay regressed to an empty production view"
fi
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

if rg -n 'TaskContext|Simulation|Vanara|User32|Gdi32|SystemControl' \
  BetterGenshinImpact/GameTask/AutoMusicGame/AutoMusicGameTask.cs \
  BetterGenshinImpact/GameTask/AutoMusicGame/AutoMusicGameRuntimePlatform.cs; then
  fail "shared AutoMusicGame task regained Windows runtime dependencies"
fi
rg -q 'AutoMusicGame holds and releases only the darkened A lane' \
  Test/BetterGenshinImpact.Core.Verification/Program.cs \
  || fail "Core verification does not execute the AutoMusicGame lane state machine"
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
rg -q 'GameTask/AutoBoss/\*\.cs' BetterGenshinImpact.Core/BetterGenshinImpact.Core.csproj \
  || fail "upstream AutoBoss sources are not linked into Core"
rg -Fq 'Descriptor("AutoBoss", "自动首领讨伐", true)' \
  BetterGenshinImpact.Core.Host/Runtime/SoloTaskCoordinator.cs \
  || fail "AutoBoss is not exposed by the truthful Core solo-task catalog"
rg -q 'new AutoBossTask' BetterGenshinImpact.Core.Host/Runtime/MacDispatcherRuntimePlatform.cs \
  || fail "macOS dispatcher does not execute the upstream AutoBoss task"
if rg -n 'TaskContext|new PathExecutor|PathExecutorPlatform\.Current|PathExecutorAutoSkipPlatform\.Current' \
  BetterGenshinImpact/GameTask/AutoBoss/AutoBossTask.cs; then
  fail "shared AutoBoss task resolves Windows or process-global PathExecutor dependencies"
fi
rg -q 'AutoBoss creates PathExecutor through the explicit Core factory' \
  Test/BetterGenshinImpact.Core.Verification/Program.cs \
  || fail "Core verification does not prove AutoBoss PathExecutor factory usage"
rg -q 'solo.start did not execute the shared AutoBoss dispatcher request' \
  Test/BetterGenshinImpact.Core.Host.Verification/Program.cs \
  || fail "Core Host verification does not exercise AutoBoss solo start"
rg -q 'Shared dispatcher AutoBoss entry did not preserve the upstream parameter object' \
  Test/BetterGenshinImpact.Core.Host.Verification/Program.cs \
  || fail "Core Host verification does not exercise parameterized AutoBoss dispatch"
rg -q '"solo.settings.get" => _soloTaskSettings.Get' BetterGenshinImpact.Core.Host/CoreRpcServer.cs \
  || fail "Core Host does not own independent-task settings reads"
rg -q '"solo.settings.save" => _soloTaskSettings.Save' BetterGenshinImpact.Core.Host/CoreRpcServer.cs \
  || fail "Core Host does not own independent-task settings writes"
for descriptor in \
  'Descriptor("AutoGeniusInvokation", "自动七圣召唤", true)' \
  'Descriptor("AutoWood", "自动伐木", true)' \
  'Descriptor("AutoBoss", "自动首领讨伐", true)' \
  'Descriptor("AutoDomain", "自动秘境", true)' \
  'Descriptor("AutoArtifactSalvage", "自动分解圣遗物", true)' \
  'Descriptor("AutoMusicGame", "自动千音雅集", true)' \
  'Descriptor("AutoAlbum", "自动千音雅集（整个专辑）", true)' \
  'Descriptor("AutoCook", "自动烹饪", true)'; do
  rg -Fq "${descriptor}" BetterGenshinImpact.Core.Host/Runtime/SoloTaskCoordinator.cs \
    || fail "composed independent-task settings are missing from the truthful catalog: ${descriptor}"
done
rg -q '"AutoRedeemCode", "自动使用兑换码", true' \
  BetterGenshinImpact.Core.Host/Runtime/SoloTaskCoordinator.cs \
  || fail "AutoRedeemCode input task is missing from the truthful Core catalog"
rg -q 'settingsAvailable = settings\.IsAvailable\(name\)' \
  BetterGenshinImpact.Core.Host/Runtime/SoloTaskCoordinator.cs \
  || fail "independent-task setting availability is not derived from the Core settings catalog"
rg -qx 'UseRedeemCode' MacGI/Resources/game-task-assets.manifest \
  || fail "composed UseRedeemCode assets are missing from the canonical package manifest"
rg -q 'new UseRedemptionCodeTask' \
  BetterGenshinImpact.Core.Host/Runtime/MacDispatcherRuntimePlatform.cs \
  || fail "macOS dispatcher does not execute the upstream UseRedemptionCode task"
for callback in clipboard.write clipboard.clear; do
  rg -Fq "case \"${callback}\"" \
    MacGI/Sources/MacGI/Runtime/BetterGICorePlatformAdapter.swift \
    || fail "Swift platform adapter is missing authenticated ${callback} handling"
done
if rg -n 'System\.Windows|TaskContext|App\.GetLogger|UIDispatcherHelper|Vanara' \
  BetterGenshinImpact/GameTask/UseRedeemCode/UseRedemptionCodeTask.cs; then
  fail "shared UseRedemptionCode task still resolves Windows-only dependencies"
fi
rg -q 'new AutoGeniusInvokationTask' \
  BetterGenshinImpact.Core.Host/Runtime/MacDispatcherRuntimePlatform.cs \
  || fail "macOS dispatcher does not execute the upstream AutoGeniusInvokation task"
if rg -n 'GeniusInvokationControl\.GetInstance|TaskContext|App\.GetLogger|SystemControl|ClickExtension|Simulation' \
  BetterGenshinImpact/GameTask/AutoGeniusInvokation; then
  fail "shared AutoGeniusInvokation still resolves process-global or Windows-only dependencies"
fi
rg -q 'new AutoAlbumTask' \
  BetterGenshinImpact.Core.Host/Runtime/MacDispatcherRuntimePlatform.cs \
  || fail "macOS dispatcher does not execute the upstream AutoAlbum task"
if rg -n 'TaskContext|Service\.Notification|App\.GetLogger' \
  BetterGenshinImpact/GameTask/AutoMusicGame/AutoAlbumTask.cs; then
  fail "shared AutoAlbum still resolves process-global or Windows-only dependencies"
fi
rg -q 'solo.settings.save did not preserve AutoBoss model semantics' \
  Test/BetterGenshinImpact.Core.Host.Verification/Program.cs \
  || fail "Core Host verification does not cover independent-task settings semantics"
rg -q 'solo.settings.save did not preserve upstream AutoDomain settings' \
  Test/BetterGenshinImpact.Core.Host.Verification/Program.cs \
  || fail "Core Host verification does not cover AutoDomain settings persistence"
rg -q 'autoDomainConfig\.sundaySelectedValue' \
  Test/BetterGenshinImpact.Core.Host.Verification/Program.cs \
  || fail "Core Host verification does not preserve hidden AutoDomain fields"
for config_section in autoDomainConfig autoFightConfig autoArtifactSalvageConfig; do
  rg -Fq "root[\"${config_section}\"]" \
    BetterGenshinImpact.Core.Host/Runtime/SoloTaskSettingsCatalog.cs \
    || fail "AutoDomain settings do not atomically update ${config_section}"
done
rg -q 'solo.settings.save did not preserve upstream AutoArtifactSalvage settings' \
  Test/BetterGenshinImpact.Core.Host.Verification/Program.cs \
  || fail "Core Host verification does not cover AutoArtifactSalvage settings persistence"
rg -q 'autoArtifactSalvageConfig\.regularExpression' \
  Test/BetterGenshinImpact.Core.Host.Verification/Program.cs \
  || fail "Core Host verification does not preserve hidden AutoArtifactSalvage fields"
rg -q 'settingsAvailable: item\["settingsAvailable"\]' \
  MacGI/Sources/MacGI/Runtime/BetterGICoreProcessSupervisor.swift \
  || fail "Swift does not consume Core-owned independent-task settings capability"
if rg -n 'Image\(systemName: "chevron.down"\)' \
  MacGI/Sources/MacGI/Components/BGIComponents.swift; then
  fail "production task cards contain an unconditional fake disclosure chevron"
fi
if rg -n '"window\.activate"' BetterGenshinImpact.Core.Host/Runtime MacGI/Sources/MacGI; then
  fail "macOS production task adapters can still force the game window to the foreground"
fi
if rg -n 'postToPid' MacGI/Sources/MacGI BetterGenshinImpact.Core.Host; then
  fail "experimental targeted CGEvent input entered a production target"
fi
rg -q 'macOS input did not pause while the selected game was unfocused' \
  Test/BetterGenshinImpact.Core.Host.Verification/Program.cs \
  && rg -q 'focus resume did not release stale input state before continuing' \
  Test/BetterGenshinImpact.Core.Host.Verification/Program.cs \
  || fail "Core Host verification does not enforce pause-until-focused input semantics"
if rg -n 'addTestLog\(\)' MacGI/Sources/MacGI/App/HUDPanelController.swift; then
  fail "production HUD still emits synthetic Core heartbeat logs"
fi

if ! rg -q 'runtime\.refreshGeometry' BetterGenshinImpact.Core.Host/CoreRpcServer.cs \
    || ! rg -q 'runtime\.geometry-refresh' BetterGenshinImpact.Core.Host/CoreRpcServer.cs \
    || ! rg -q 'scheduleRuntimeGeometryRefresh\(for: refreshed\.capturePixelSize\)' MacGI/Sources/MacGI/App/AppState.swift; then
    echo "Core geometry refresh is not wired from pixel-size changes" >&2
    exit 1
fi

if ! rg -q 'window\.captureRect' MacGI/Sources/MacGI/App/HUDPanelController.swift \
    || rg -q 'setFrame\(Self\.appKitFrame\(forQuartzFrame: window\.frame' MacGI/Sources/MacGI/App/HUDPanelController.swift; then
    echo "HUD must follow the game client rectangle, not the Wine frame" >&2
    exit 1
fi

if ! rg -q 'x: size\.width - 235 \* scale' MacGI/Sources/MacGI/Views/HUDView.swift \
    || ! rg -q 'y: size\.height - 27 \* scale' MacGI/Sources/MacGI/Views/HUDView.swift \
    || ! rg -q 'width: 178 \* scale' MacGI/Sources/MacGI/Views/HUDView.swift \
    || ! rg -q 'height: 22 \* scale' MacGI/Sources/MacGI/Views/HUDView.swift; then
    echo "UID cover no longer matches the upstream right-bottom rectangle" >&2
    exit 1
fi
rg -q 'mac-core-extraction' .github/workflows/wpf-build.yml \
  || fail "Windows WPF build does not gate mac-core-extraction pushes"
rg -q 'startupPollLimit = 4_800' MacGI/Sources/MacGI/Runtime/BetterGICoreProcessSupervisor.swift \
  && test "$(rg -c '0\.\.<Self\.startupPollLimit' MacGI/Sources/MacGI/Runtime/BetterGICoreProcessSupervisor.swift)" -eq 2 \
  || fail "Swift does not allow the Core Host a bounded 120-second native cold-start window"
rg -q '#if DEBUG' MacGI/Sources/MacGI/Runtime/BetterGICoreProcessSupervisor.swift \
  && rg -q 'resolveDevelopmentExecutableURL' MacGI/Sources/MacGI/Runtime/BetterGICoreProcessSupervisor.swift \
  || fail "SwiftPM Debug builds cannot locate the staged BetterGI Core Helper"
rg -q 'setActivationPolicy\(\.regular\)' MacGI/Sources/MacGI/App/MacGIApp.swift \
  || fail "macOS frontend does not register as a regular Dock application"
rg -q 'CFBundlePackageType string APPL' MacGI/scripts/package-macgi-app.sh \
  && rg -q 'CFBundleIdentifier string \$\{bundle_identifier\}' MacGI/scripts/package-macgi-app.sh \
  && rg -q 'NSScreenCaptureUsageDescription' MacGI/scripts/package-macgi-app.sh \
  || fail "macOS App packaging does not create a standard APPL bundle identity"
rg -q 'MACGI_ALLOW_ADHOC_SIGNING' MacGI/scripts/package-macgi-app.sh \
  && ! rg -q 'signing_identity=\${signing_identity:--}' MacGI/scripts/package-macgi-app.sh \
  || fail "macOS local packaging can silently fall back to an unstable ad-hoc TCC identity"
rg -q 'Contents/Resources/BetterGICore' MacGI/scripts/package-bettergi-core.sh \
  && rg -q 'Resources/BetterGICore/BetterGenshinImpact.Core.Host' \
    MacGI/Sources/MacGI/Runtime/BetterGICoreProcessSupervisor.swift \
  || fail "macOS App and Swift runtime disagree on the sealed Core publish-tree location"
if rg -n 'LSUIElement|LSBackgroundOnly' MacGI/scripts/package-macgi-app.sh; then
  fail "macOS App packaging hides the frontend from the Dock"
fi
rg -q '"--parent-pid", String\(ProcessInfo\.processInfo\.processIdentifier\)' \
  MacGI/Sources/MacGI/Runtime/BetterGICoreProcessSupervisor.swift \
  && rg -q 'OptionalPositiveIntArgument\(args, "--parent-pid"\)' BetterGenshinImpact.Core.Host/Program.cs \
  && rg -q 'new ParentProcessLifetime\(processId\)\.MonitorAsync' BetterGenshinImpact.Core.Host/Program.cs \
  || fail "Core Host is not bound to the Swift parent-process lifetime"
rg -q 'appState\.startRuntime\(\)' MacGI/Sources/MacGI/Views/Pages/OverviewPage.swift \
  && fail "The global runtime button regressed to a start-only action"
rg -q 'appState\.toggleRuntime\(\)' MacGI/Sources/MacGI/Views/Pages/OverviewPage.swift \
  && rg -q 'runtime\.start' BetterGenshinImpact.Core.Host/CoreRpcServer.cs \
  && rg -q 'runtime\.stop' BetterGenshinImpact.Core.Host/CoreRpcServer.cs \
  || fail "The global runtime control is not backed by Core start/stop RPC"
rg -q 'guard runtimeLifecycle == \.running' MacGI/Sources/MacGI/App/AppState.swift \
  && rg -q 'runtimeLifecycle == \.running' MacGI/Sources/MacGI/App/AppState.swift \
  || fail "The scheduler can start while the Core trigger runtime is stopped"
rg -q 'catalog\.setScriptGroupProjectEnabled' BetterGenshinImpact.Core.Host/CoreRpcServer.cs \
  && rg -q 'setSchedulerProjectEnabled' MacGI/Sources/MacGI/Views/Pages --glob '*.swift' \
  || fail "Script-group project status is not edited through the Core catalog"
if rg -n 'PathExecutorPlatform\.Current|PathExecutorAutoSkipPlatform\.Current|ScriptGroupExecutionServices\.Current' \
  BetterGenshinImpact/Core/Script/Dependence/AutoPathingScript.cs; then
  fail "The production pathingScript host still resolves process-global execution services"
fi
rg -q '_executionServices\.CreatePathExecutor' \
  BetterGenshinImpact/Core/Script/Dependence/AutoPathingScript.cs \
  || fail "The production pathingScript host is not constructor-injected"
if rg -n 'Toggle\("", isOn: \.constant\(project\.status' MacGI/Sources/MacGI/Views/Pages --glob '*.swift'; then
  fail "Scheduler project controls regressed to a read-only fake toggle"
fi
if rg -n 'Toggle\("(Dry-Run|真实输入|Core Runtime Input)"' MacGI/Sources/MacGI/Views/Pages --glob '*.swift'; then
  fail "Development input authorization controls are exposed in production UI"
fi
rg -q -- '--dry-run' MacGI/Sources/MacGI/App/AppState.swift \
  || fail "Dry-Run is not controlled by an explicit launch argument"
if rg -n -- '--allow-real-input' MacGI/Sources/MacGI Docs/core-extraction-map.md; then
  fail "Real input incorrectly requires a command-line opt-in"
fi
rg -q '@Published var isHUDVisible = false' MacGI/Sources/MacGI/App/AppState.swift \
  && rg -q 'if self\.showHUDOnStart' MacGI/Sources/MacGI/App/AppState.swift \
  || fail "HUD visibility is not bound to successful runtime start/stop"
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
rg -q 'trigger\.SupportsGameUiCategory\(content\.CurrentGameUiCategory\)' \
  BetterGenshinImpact/GameTask/TaskTriggerDispatcher.cs \
  || fail "Windows trigger dispatcher does not honor shared multi-category trigger semantics"
rg -q 'trigger\.SupportsGameUiCategory\(currentCategory\)' \
  BetterGenshinImpact.Core.Host/Runtime/MacTriggerDispatcher.cs \
  || fail "macOS trigger dispatcher does not honor shared multi-category trigger semantics"
rg -q 'MapMask did not preserve its upstream main-UI behavior while adding stable big-map updates' \
  Test/BetterGenshinImpact.Core.Host.Fast.Verification/TriggerSettingsSuite.cs \
  || fail "MapMask stable big-map category behavior is not verified"
rg -q 'category is GameUiCategory\.Unknown or GameUiCategory\.BigMap' \
  BetterGenshinImpact/GameTask/MapMask/MapMaskTrigger.cs \
  || fail "MapMask does not declare both upstream main and big-map UI categories"
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
