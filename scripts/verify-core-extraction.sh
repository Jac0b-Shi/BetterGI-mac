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

rg -q 'Core/Script/Dependence/Dispatcher.cs' BetterGenshinImpact.Core/BetterGenshinImpact.Core.csproj \
  || fail "shared upstream Dispatcher is not linked into Core"
rg -q 'AddHostObject\("dispatcher", new Dispatcher' \
  BetterGenshinImpact.Core.Host/Runtime/MacScriptProjectHostInitializer.cs \
  || fail "ClearScript dispatcher host is not registered"
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
