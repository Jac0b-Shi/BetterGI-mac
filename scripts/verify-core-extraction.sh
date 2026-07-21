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
