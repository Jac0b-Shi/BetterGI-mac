# BetterGI → macOS 全量移植清单

> 历史规划快照。本文件包含已经废弃的 Swift、JavaScriptCore、Rust 与
> mock fallback 方案，不得作为当前生产架构依据。当前所有权与完成证据以
> `../../Docs/core-extraction-map.md`、`../../Docs/core-feature-parity-audit.md`
> 和 `architecture.md` 为准。
>
> 基于 upstream BetterGI v0.61.3-alpha.1 的完整审计。
> 原始代码量：~874 个 .cs 文件，~129,000 行 C#。
> macOS 移植估算：~50,000+ 行需要实质修改或重写。

---

## 一、必须重写的底层基础设施（macOS 无等价物）

### 1.1 游戏截图捕获 ⚠️ 完全重写

| Windows 原实现 | macOS 替代 |
|---|---|
| BitBlt (GDI) | 删除 |
| Windows Graphics Capture (SharpDX/D3D11) | 删除 |
| DwmSharedSurface | 删除 |
| PresentMonFPS | 删除 |
| **—** | **ScreenCaptureKit** (macOS 12.3+) |
| **—** | **CGWindowListCreateImage** (兼容旧版) |

**文件**: `Fischless.GameCapture/` 整个子项目 (~2000 行) → 全部重写为 Swift

### 1.2 输入模拟 ⚠️ 完全重写

| Windows | macOS |
|---|---|
| SendInput (Win32) | CGEventPost / CGEventCreateKeyboardEvent |
| PostMessage (WM_KEYDOWN) | N/A（macOS 无窗口消息队列，用 CGEvent） |
| MouseEventSimulator | CGEvent 鼠标事件 + 坐标映射 |
| Global hotkey (RegisterHotKey) | CGEvent tap / Carbon Event Monitor |

**文件**: `Fischless.WindowsInput/` (~1500 行) → 全部重写为 Swift

### 1.3 音频采集 ⚠️ 重写

| Windows | macOS |
|---|---|
| WASAPI loopback capture (SileroVadDetector) | AVAudioEngine / AudioUnit |

**用途**: 自动剧情中检测语音结束再推进对话。

### 1.4 UI 框架 ⚠️ 完全重写

| Windows | macOS |
|---|---|
| WPF + WinForms | **已完成** — SwiftUI + AppKit |
| MaskWindow (WPF 透明浮窗) | HUD NSPanel（已完成原型） |

**当前状态**: UI 原型已完成，不需要再移植。

---

## 二、可移植的核心识别链路（C#逻辑 → Swift，底层模型不变）

### 2.1 OCR 文字识别 ✅ ONNX 模型跨平台

**原项目文件**:
- `Core/Recognition/OCR/Paddle/PaddleOcrService.cs` — 两阶段管道（Det → Rec）
- `Core/Recognition/OCR/Paddle/Det.cs` — 文字检测
- `Core/Recognition/OCR/Paddle/Rec.cs` — 文字识别
- `Core/Recognition/OCR/OcrFactory.cs` — 模型选择
- `Core/Recognition/OCR/OcrResult.cs` — 结果模型

**ONNX 模型文件**（直接可用）:
- `PP-OCRv4_mobile_det_infer/slim.onnx` — 检测
- `PP-OCRv4_mobile_rec_infer/slim.onnx` — 中文识别
- `PP-OCRv4_mobile_rec_V4En/slim.onnx` — 英文/数字
- `PP-OCRv5_*` 系列 — 多语言

**macOS 实现方案**:
- `onnxruntime` Swift package（或 C wrapper）
- 参考原项目 Pipeline: CapturedFrame → ROI crop → Det infer → crop regions → Rec infer → OCRResult

**当前代码状态**:
- ✅ `CapturedFrame` 模型已定义
- ✅ `NormalizedROI` + `clampedPixelRect()` 已定义
- ✅ `OCRResult` 模型已定义（含 Region、combinedText、contains/regex）
- ✅ `PaddleOCROnnxRuntime` 已接入 ONNX Runtime SwiftPM 1.24.2
- ✅ `PaddleOCRPreprocessor` 已按 BGI BGR/CHW/Normalize 流程处理 Det/Rec 输入
- ✅ `PaddleOCRRecognitionEngine` 已输出 `RecognitionObservation`
- ⚠️ Det 后处理目前是 connected-components 过渡实现，还不是 BGI/OpenCV 的旋转框轮廓后处理

### 2.2 模板匹配 ✅ OpenCV 跨平台

**原项目文件**:
- `Core/Recognition/OpenCv/MatchTemplateHelper.cs` — 匹配引擎
- `Core/Recognition/RecognitionObject.cs` — 统一识别对象定义
- `Core/Recognition/RecognitionTypes.cs` — 枚举：TemplateMatch/ColorMatch/OcrMatch/Ocr/ColorRangeAndOcr/Detect

**模板图片**（直接可用）:
```
GameTask/AutoPick/Assets/   — F 键图标等
GameTask/AutoSkip/Assets/   — 跳过按钮、选项气泡、X 按钮等
GameTask/AutoEat/Assets/    — NRE 状态图标等
GameTask/AutoFishing/Assets/ — 退出钓鱼按钮等
GameTask/MapMask/Assets/     — 地图 tile
```
所有 `.png` 文件直接可用，仅需按当前分辨率缩放。

**macOS 实现方案**:
- `opencv2` Swift Package（或自己编译 C++ 桥接）
- 实现 `Find` (单模板匹配) 和 `FindMulti` (多目标匹配)
- 支持 MatchMode: `TM_CCOEFF_NORMED` (默认), `TM_SQDIFF_NORMED`

**当前代码状态**:
- ✅ 窗口帧尺寸已通过 `CapturedFrame` 获取
- ✅ `RecognitionObject` / `RecognitionTypes` / ROI / threshold / match mode 已定义
- ✅ P0 模板 PNG 已嵌入 `Sources/MacGI/Resources/GameTask/...`
- ✅ `TemplateMatchingRecognitionEngine` 已支持 Swift 侧单模板匹配、ROI、多目标候选抑制
- ✅ `AutoSkip.OptionIconRo` 已按上游 `FindMulti` 场景请求 8 个多目标 observation
- ✅ 模板资源加载已按 BGI `SystemInfo.AssetScale` 规则缩放：当前帧宽度低于 1920 时使用 `frameWidth / 1920`，高于 1920 时不放大
- ⚠️ Small-window template downscaling is a MacGI compatibility path for YAAGL/windowed captures, not a claim that BetterGI officially supports sub-1080 gameplay windows. 2K/4K behavior should be validated separately and should not blindly upscale templates unless upstream-compatible evidence requires it.
- ✅ `AutoSkip.DailyRewardIconRo` / `AutoSkip.ExploreIconRo` 已按上游 `AutoSkipAssets` 接入 P0 资源覆盖
- ✅ `macgi-core::recognition::pixel_template::PixelTemplateMatcher` 已能消费 BGRA 帧 + PNG 模板并输出 normalized rect
- ✅ `shared/macgi_core.h` / `macgi_core_match_template` / `RustCoreBridge.recognizeTemplates` 已接通 Swift → Rust 模板 observation 路径
- ✅ `BGIAssetResolver` 已兼容上游 `GameTaskManager.LoadAssetImage(feature, asset)` 的 `feature:asset` 别名解析，支持 `AutoSkip:icon_option.png` → `GameTask/AutoSkip/Assets/1920x1080/icon_option.png` 并沿用 `AssetScale` 缩放
- ✅ JS `BvImage` direct upstream resource path 与 `feature:asset` 别名均可通过 `BGICapturingJSScriptHostEnvironment` 默认 Swift 模板引擎识别；Rust 模板链路仍由 main-actor `AppState` observation provider 使用
- ✅ 真实凯瑟琳对话中途帧已 dry-run 验证 Rust AutoSkip 输出 `Space`，符合 BGI `QuicklySkipConversationsEnabled` 跳过剧情路径
- ✅ `targetObservationIndex` → `InputAction.leftClick` 的屏幕坐标解析已单元验证，并对异常/越界 rect 做安全丢弃
- ✅ Rust AutoSkip 已按上游 `ChatOptionChoose` 内置分支优先选择 `DailyRewardIconRo` / `ExploreIconRo` 和带“每日/委托/探索/派遣”关键词的选项 observation
- ✅ 真实凯瑟琳选项帧已 dry-run 验证 `DailyRewardIconRo` / `ExploreIconRo` 识别与每日委托目标选择
- ⚠️ 最终 OpenCV 加速后端、真实输入点击端到端验收仍待补齐

### 2.3 YOLO 目标检测 ✅ ONNX 模型跨平台

**模型文件**（直接可用）:
- `BgiFish` — 鱼群检测
- `BgiTree` — 树木检测
- `BgiWorld` — 世界物体检测
- `BgiMine` — 矿石检测
- `BgiAvatarSide` — 侧边栏头像检测（战斗系统用）
- `BgiQClassify` — Q 技能就绪分类
- `BgiMap` — 地图定位

**macOS 实现方案**:
- Swift wrapper around ONNX Runtime
- YOLO post-processing: NMS + coordinate scaling

**当前代码准备**:
- ✅ 帧坐标系统已通过 `CapturedFrame` 建立
- ✅ `BGIOnnxModel` 已按上游 `BgiOnnxModel.cs` 注册 Yap / PaddleOCR V4+V5 / YOLO / VAD 模型路径
- ✅ `BGIModelAssetResolver` 已支持 `Bundle.module` 内置资源与 `~/Library/Application Support/betterGI-mac/` 首次下载资源双路径解析
- ✅ `BGIExternalResourceInstaller` 已支持从已解压 `contentFiles/any/any` 或 `.nupkg`/zip 安装 BetterGI 资源包到运行时目录
- ✅ `BGIExternalResourceBootstrapper` 已支持启动时 coverage 检查、NuGet flat-container 下载源、`Cache/Downloads` 缓存和镜像回退
- ✅ `YOLODetectionPostProcessor` 已实现 letterbox 坐标还原、confidence 过滤、同类别 NMS、按类别分组
- ⚠️ 真实 YOLO ONNX session / label metadata / Detect trigger 接入仍待补齐

---

## 三、触发器（Trigger）— 核心自动化逻辑

每个触发器 = 一个 `ITaskTrigger` 实现，在 ~50ms 的帧循环中运行。

### 3.1 AutoPick — 自动拾取 🔴 高优先级

| 项目 | 内容 |
|---|---|
| 原代码量 | ~400 行 + 模板图片 |
| 触发频率 | 每帧（50ms），占空比 ~50% |
| 识别方式 | 模板匹配 F 键图标 → OCR 物品名 → 白/黑名单 |
| 动作 | Press F |

**需要移植的素材**:
- `Assets/自动拾取/f_icon.png` — F 键模板
- `Assets/自动拾取/chat_icon.png` — 对话气泡（排除用）
- `Assets/自动拾取/settings_icon.png` — 设置图标（排除用）
- `Assets/自动拾取/l_icon.png` — L 键（千星奇域跳过用）
- `Assets/自动拾取/scroll_upper.png` — 滚动条上端（黑名单检测用）

**OCR 文本后处理**: 括号规范化、空白裁剪、中文过滤、引号配对。

### 3.2 AutoSkip — 自动剧情 🔴 高优先级

| 项目 | 内容 |
|---|---|
| 原代码量 | ~1285 行（最大最复杂的触发器） |
| 触发频率 | 每帧 |
| 识别方式 | 模板匹配 + OCR + 颜色检测 + 轮廓分析 + VAD 语音结束检测 |

**功能子模块**（按出现顺序）:
1. **跳过按钮** — 检测并点击左上角跳过按钮
2. **对话框选项** — 检测选项气泡 → OCR 选项文本 → 自动选择
3. **弹出关闭** — 检测物品获得/角色获得弹窗 → 点击关闭
4. **物品提交** — 检测感叹号 + OCR → 自动提交
5. **邀约事件** — 检测邀约选项（选中/未选中）→ 按策略选择
6. **每日奖励** — 检测原石图标 → 自动领取
7. **探索派遣** — 检测并完成派遣
8. **语音检测** — VAD 等待语音结束再推进对话

**需要移植的素材**:
- `Assets/自动剧情/` — 多个模板 PNG

### 3.3 AutoFishing — 自动钓鱼 🟡 中优先级

| 项目 | 内容 |
|---|---|
| 原代码量 | ~800 行 + YOLO 模型 |
| 识别方式 | 模板匹配（检测钓鱼UI入口） + YOLO BgiFish（鱼位置） |
| 动作 | 抛竿 → 咬钩检测 → 收线（进度条追踪） |
| 独占性 | IsExclusive = true（钓鱼时不跑其他 trigger） |

**模型依赖**: `BgiFish` ONNX 模型

### 3.4 AutoEat — 自动吃药 🟡 中优先级

| 项目 | 内容 |
|---|---|
| 原代码量 | ~300 行 |
| 识别方式 | 模板匹配 NRE 状态 + 像素颜色检测低血量 + 模板检测复活食物 |
| 动作 | 按下 NRE 快捷键 / 复活食物 |

### 3.5 MapMask — 地图遮罩 🟡 中优先级

| 项目 | 内容 |
|---|---|
| 原代码量 | ~5000+ 行 |
| 识别方式 | 小地图提取 → 模板匹配定位 → 地图 tile 坐标系统 |
| 渲染 | 遮罩窗口上标绘传送点/矿点/Boss/路径 |

**地图 Tile 数据**: `BetterGI.Assets.Map` NuGet 包（PNG 文件）

### 3.6 SkillCd — 技能冷却显示 🟢 低优先级

| 项目 | 内容 |
|---|---|
| 原代码量 | ~500 行 |
| 识别方式 | 模板匹配头像图标 + OCR 角色名 + ONNX BgiQClassify |
| 渲染 | 遮罩窗口上绘制冷却倒计时 |

### 3.7 GameLoading — 自动进入游戏 🟢 低优先级

| 项目 | 内容 |
|---|---|
| 原代码量 | ~300 行 |
| 功能 | 检测"进入游戏"门图标 → 点击进入 → 跳过加载画面 |

---

## 四、Solo Task（独立任务）— 长流程自动化

每个 SoloTask 在 TaskRunner 中运行，期间独占所有触发器。

| 任务 | 原代码量 | 核心依赖 | 优先级 |
|---|---|---|---|
| **AutoDomain** — 秘境刷本 | ~2000 行 | 战斗脚本 + 识别 + 输入 | 🟡 |
| **AutoFight** — 自动战斗 | ~5000 行 | 战斗 DSL 脚本 + Avatar 数据库 | 🟡 |
| **AutoBoss** — Boss 讨伐 | ~1000 行 | 战斗 + 传送 + 寻路 | 🟢 |
| **AutoWood** — 木材采集 | ~500 行 | YOLO BgiTree + 输入 | 🟢 |
| **AutoLeyLineOutcrop** — 地脉花 | ~800 行 | 战斗 + 传送 | 🟢 |
| **AutoTrackPath** — 路径行走 | ~1000 行 | Recording + Navigation | 🟢 |
| **AutoGeniusInvokation** — 七圣召唤 | 未详 | 卡牌识别 + 决策 | ⚪ |
| **AutoMusicGame** — 音游 | 未详 | 实时音符识别 | ⚪ |
| **AutoArtifactSalvage** — 圣遗物分解 | ~500 行 | OCR 圣遗物属性 | 🟢 |
| **AutoCook** — 自动烹饪 | ~300 行 | 模板匹配 | 🟢 |
| **AutoOpenChest** — 开宝箱 | 未详 | 识别 + 寻路 | ⚪ |

---

## 五、Script（JS 脚本引擎）

### 5.1 引擎层

| 组件 | 原实现 | macOS 方案 |
|---|---|---|
| JS 引擎 | Microsoft.ClearScript.V8 (win-x64) | C# Core Host 使用 ClearScript V8 `osx-arm64` |
| WebView2 | Microsoft.Web.WebView2 | Swift 平台层使用 WKWebView |
| HTML 遮罩 | WPF WebView2 overlay | Core 保留上游 `htmlMask` 合同，Swift 负责 WKWebView 窗口与消息桥 |

### 5.2 Script API Surface

JS 脚本可调用的能力（`genshin.*` 全局对象）:

| API | 功能 | 依赖 |
|---|---|---|
| `Tp(x, y)` | 传送 | 地图跟踪 + 输入 |
| `GetPositionFromMap()` | 获取当前位置 | 地图跟踪 |
| `GetCameraOrientation()` | 相机朝向 | 小地图分析 |
| `SwitchParty(name)` | 切换队伍 | 输入 + 识别 |
| `ChooseTalkOption(text)` | 选择对话 | OCR + 输入 |
| `MoveMapTo(x,y)` | 移动大地图 | 输入 |
| `SetTime(h,m)` | 调整时间 | 输入 + 识别 |
| `AutoFishing()` | 启动钓鱼 | 钓鱼触发器 |
| `Relogin()` | 重新登录 | 输入 |
| `LazyNavigationInstance` | 自动寻路 | 地图跟踪 + 输入 |

| 全局方法 | 功能 | 依赖 |
|---|---|---|
| `sleep(ms)` | 异步等待 | — |
| `keyDown/Up/Press(key)` | 按键 | 输入模拟 |
| `moveMouseTo(x,y)` | 鼠标移动 | 输入模拟 |
| `click(x,y)` | 鼠标点击 | 输入模拟 |
| `captureGameRegion()` | 截图 | 截图捕获 |
| `getAvatars()` | 获取队伍 | 头像识别 OCR |

**当前代码准备**:
- ✅ `BGIScriptRepositoryCatalogLoader` 已支持解析 `repo.json` 递归 `indexes` 树，保留 path/version/author/tags/lastUpdated/hasUpdate 等仓库元数据
- ✅ `BGIJSScriptManifest` 已按上游 `Manifest.cs` 支持 `manifest_version`、`bgi_version`、`settings_ui`、`saved_files`、`library`、`http_allowed_urls` 等字段
- ✅ `BGIJSScriptSettingItem` 已支持 `settings.json` 的 `separator`、`input-text`、`select`、`checkbox`、`multi-checkbox`、`cascade-select` 元数据承载
- ✅ `BGIScriptRepositoryUpdateMarkerGenerator` 已支持按目录重合度继承上次 `repo_updated.json`，递归生成 `hasUpdate`/`lastUpdated` 更新标记
- ✅ `BGIScriptSubscriptionStore` 已支持 `User/Subscriptions/{repoName}.json`、`bettergi://script?import=` URL 解码、裸顶层路径展开和订阅路径清理
- ✅ `BGIScriptRepositoryWebBridge` 已覆盖上游 `RepoWebBridge` 的服务层能力：`repo_updated.json`/`repo.json` 读取、仓库文件读取、订阅 JSON、import URI、清空/重置 `hasUpdate`
- ✅ JS checkout 已支持 `manifest.json` `saved_files` 备份恢复，并按上游 `ResolveScriptDependencies()` 扫描 `packages/...` import/require 依赖
- ✅ `BGIJSScriptRunner` 已提供 JavaScriptCore 第一层 runtime：加载已安装 `User/JsScript/{folder}` 项目、注入 `settings`、解析 `library`/`.`/`./packages`、重写资源 import、执行 packages 模块，并暴露 `log`/`file`/输入全局函数/`genshin.*` host API
- ✅ `BGIJSScriptHostEnvironment` 已把 JS host 调用整理成 typed input / `genshin.*` command；默认环境用于测试记录，`BGIInputDispatchingJSScriptHostEnvironment` 可将支持的 JS 输入命令转入既有 `InputAction` / `CGEventInputDispatcher`
- ✅ `genshin.*` 第一层 bridge 已支持上游属性与参数/返回值形态：`Width`/`width`、`Height`/`height`、`ScaleTo1080PRatio`/`scaleTo1080PRatio`、`ScreenDpiScale`/`screenDpiScale`，`Tp` map/force 重载，`MoveMapTo(forceCountry)`，`MoveIndependentMapTo`，`GetBigMapZoomLevel` / `SetBigMapZoomLevel`，`GetPositionFromBigMap`，`GetPositionFromMap(map, matching, cache, nearX, nearY)`，`GetPositionFromMapWithMatchingMethod(map, matching, cache)`，`ReturnMainUi`，`TpToStatueOfTheSeven`，`ChooseTalkOption(skipTimes,isOrange)`，`AutoFishing(policy)`，`SetTime(skip)`；返回值可承载 bool/int/double/`x,y,X,Y`
- ✅ `BGICapturingJSScriptHostEnvironment` 已把上游 `BvStatus.GetBigMapScale` / `TpTask.GetBigMapZoomLevel` 的第一层语义接到 `genshin.GetBigMapZoomLevel()`：每次调用重新截图，使用 `QuickTeleport.MapScaleButtonRo` 中心 Y 按 `TpConfig.ZoomStartY=468`、`ZoomEndY=612` 先计算内部 scale fraction，再按上游 `(-5 * scale) + 6` 返回脚本侧 1.0...6.0 缩放等级；不在大地图或识别不到缩放按钮时抛错，而不是返回伪造默认值
- ✅ `BvPage.Keyboard` / `BvPage.Mouse` 已接入第一层输入对象兼容：`KeyPress/KeyDown/KeyUp`、`MoveMouseBy/MoveMouseTo`、左右/中键 click/down/up、`VerticalScroll` 均复用 typed input command
- ✅ JS host 已补 `captureGameRegion()` 返回的 capture metadata 对象，并提供 `Ocr/ocr()` 入口；`BGICapturingJSScriptHostEnvironment` 可注入 `CaptureImageFrame` 与 OCR provider，向脚本返回 BGI 风格 `Text` / `Regions`
- ✅ `captureGameRegion()` 已补第一层 ImageRegion 兼容入口：`Find` 可接受 `BvImage` template、`RecognitionObject.Ocr(...)`、`RecognitionObject.OcrMatch(...)`、`RecognitionObject.ColorRangeAndOcr(...)` 或带 `Text` / `RegionOfInterest` 的 OCR recognition object；`Find(Ocr)` 按上游返回 ROI/整图 region 并写入去空白合并文本，`FindMulti(Ocr)` 返回各 OCR 子框并应用 `ReplaceDictionary`，文本过滤保留在 `BvLocator` 层；多目标 `OcrMatch` / `ColorRangeAndOcr` 与 `ColorMatch` / `Detect` 会报不支持而不是静默返回空 region
- ✅ JS `RecognitionObject` 第一层 shim 已支持 `Ocr` / `OcrMatch` / `OcrThis` / `ColorRangeAndOcr` / `ColorMatch` / `Detect` 与手动设置 `AllContainMatchText` / `OneContainMatchText` / `RegexMatchText` / `ReplaceDictionary`；`OcrMatch` 按上游规则合并 OCR 文本、去空白、替换误识别文本后再匹配，`ColorRangeAndOcr` 已通过 object-level provider 接入 `PaddleOCRRecognitionEngine`，`ColorMatch` / `Detect` 暂保持 model/shim 层承载，且通过 `ImageRegion.Find` 调用时与上游一样报不支持
- ✅ 已补第一层 `BvPage` / `BvLocator` OCR 兼容 shim：`new BvPage().Ocr(rect)`、`GetByText(text, rect).FindAll()` 会复用 `captureGameRegion().Ocr(rect)` 并按文本过滤
- ✅ 已补第一层 `BvImage` template locator 兼容 shim：`new BvImage(template, rect, threshold)`、`GetByImage(image).FindAll()` 会按上游 `BvLocator.FindAll()` 走单目标 `ImageRegion.Find`；未注入 provider 时，direct upstream resource path 与 `feature:asset` 别名会落到 Swift `TemplateMatchingRecognitionEngine`
- ✅ 已补第一层 `BvLocator` 等待/重试/点击链式语义：`WaitFor`、`TryWaitFor`、`WaitForDisappear`、`TryWaitForDisappear`、`Click(timeout)`、`DoubleClick(timeout)`、`ClickUntilDisappears(timeout)`、`WithRoi`、`WithTimeout`、`WithRetryInterval`、`WithRetryAction`，并提供常用 ROI `CutLeft/CutRight/CutTop/CutBottom/...` helper；`ClickUntilDisappears(timeout)` 已按上游只把 timeout 用于初次点击，后续用 fresh locator 默认等待消失并在重试时继续点击
- ✅ `BGIJSScriptTaskExecutor` 已提供任务级执行入口：从 `User/JsScript/{folder}` 加载已安装脚本，构造 capture/OCR/template/object-recognition host，按捕获帧刷新 game metrics，并可选将支持的 JS input command 转发到 `CGEventInputDispatcher`
- ✅ `AppState.runInstalledJSScript()` 已把 JS executor 接到应用状态层：准备真实/Mock capture frame，可用时接 PaddleOCR，记录执行结果与脚本日志，并将 JS input commands 通过既有 `InputSafetyGate` / `dispatchInput(..., .runtimeTrigger)` 路径回放；JS 页面已有手动运行/停止入口
- ✅ 调度器第一层已参考上游 `ScriptGroupProject` / `ScriptControlViewModel.GetNextGroups()` / `GetNextProjects()` / `ScriptService.RunMulti()` 建立 Swift mirror：保留 `Javascript`/`KeyMouse`/`Pathing`/`Shell` 类型字符串、`Enabled`/`Disabled`、`Schedule`、`RunNum`、`NextFlag`、`SkipFlag`、`jsScriptSettingsObject` 语义，并可从调度器顺序触发已安装 JS/KeyMouse/Shell 项目
- ✅ `KeyMouse` 调度项目已参考上游 `KeyMouseRecorder` / `KeyMouseMacroPlayer` 接入第一层回放：解析 `macroEvents`/`info` camelCase JSON，按 capture rect 与 DPI 适配坐标，支持 KeyDown/KeyUp、MouseMoveTo/MoveBy、MouseDown/Up、MouseWheel，并统一走 `InputSafetyGate`
- ✅ `Shell` 调度项目已参考上游 `ShellTask` / `ShellTaskParam.BuildFromConfig()` / `ShellConfig` 接入第一层执行器：项目 `Name` 作为命令，组级 `config.enableShellConfig` 为真时使用 `config.shellConfig`，否则使用上游默认 `disable=false`、`timeout=60`、`noWindow=true`、`output=true`，并保留 `timeout <= 0` 仅启动不等待语义
- ✅ `Pathing` 调度项目已参考上游 `PathingTask.BuildFromFilePath()` 接入第一层加载入口：从 `User/AutoPathing/{FolderName}/{Name}` 读取任务，兼容相对/绝对 `FolderName`，按 `PathRecorder.JsonOptions` 的 snake_case 字段 decode `info`/`config`/`farming_info`/`positions`，应用同目录 `control.json5` 的 `global_cover`、`json_list[].cover`、`_obj_cover`、`_arr_add` 合并规则，并把 `Info.EnableMonsterLootSplit` 传播到每个 waypoint 的 `PointExtParams`
- ✅ `BGIPathExecutor` 已参考上游 `PathExecutor.Pathing()` 建立第一层执行骨架：按 `Teleport` 切分路径段，保留切队/校验/初始化/`Navigation.WarmUp`/低血量恢复/传送/朝向/粗略移动/精确贴近/前置 action/后置 action/释放按键阶段，`Fight` 统计 `successFight`，末段完成置 `successEnd`；实际地图定位、传送、移动与 action handler 通过 `BGIPathingNavigationBackend` 注入，`AppState` 运行 Pathing 项目时会构造第一层 `BGIRealPathingNavigationBackend`
- ✅ `BGIRealPathingNavigationBackend` 已把小地图定位、相机朝向、受 `InputSafetyGate` 保护的输入、以及 `BGIBigMapInteractionService` 大地图传送点击串起来；大地图点击坐标现在从当前 `WindowInfo.captureRect` 派生，不再假设固定 1920x1080 全屏窗口，避免窗口模式/YAAGL/Wine 标题栏适配继续分散。`BGIBigMapInteractionService.openBigMap()` 有截图 provider 时已按上游 `TpTask.TryToOpenBigMapUi` 先识别当前是否在大地图，只在不在大地图时才按打开地图键，随后重试识别，避免当前已经打开大地图时反向关闭地图
- ✅ `BGIGameUIStatusRecognizer` 已按上游 `BvStatus.IsInBigMapUi` / `BigMapIsUnderground` 迁移 QuickTeleport 大地图状态模板：`MapScaleButton.png`、`MapSettingsButton.png`、`MapUndergroundSwitchButton.png`，并保留上游 ROI。真实 `wine — 原神` 大地图窗口验证通过：2026-07-03 `MACGI_RUN_REAL_BIGMAP_TESTS=1 swift test --filter RealGenshinBigMapVerificationTests`，窗口 `960×572`，`MapScaleButton` confidence `0.947`，`MapSettingsButton` confidence `0.949`；当时 raw scale fraction 约 `0.290`，脚本侧 `GetBigMapZoomLevel` 现在按上游公式返回约 `4.55`
- ✅ `BGIBigMapInteractionService.moveMapTo(...)` 已按上游 `TpTask.MoveMapTo` 接入第一层拖图循环：通过注入的 big-map center provider 获取当前大地图中心，读取 1.0...6.0 zoomLevel，用 `MapScaleFactor` 把目标坐标偏移换算为鼠标像素距离，复刻上游 zoom-out/zoom-in 判断、`MaxMouseMove` 分段、`GenerateSteps` 余弦分配、以及识别失败时的惯性预测兜底。Pathing 后端现在会在 Rust core dylib 暴露 `big-map-sift` ABI 且 `Assets/Map/Teyvat/Teyvat_0_256_SIFT.*` 存在时优先使用 `BGIBigMapSiftPositionProvider`，把 Rust 返回的 256 尺度大地图矩形中心换算到 2048 尺度 scene image，再转原神世界坐标；SIFT 不可用或无匹配时仍回落临时小地图定位兜底
- ✅ `BGIBigMapInteractionService` 已迁移上游 `QuickTeleport.TeleportButtonRo` / `MapCloseButtonRo` / `MapChooseIconRoList` 的第一层确认路径：点击目标坐标后优先重新截图识别 `GoTeleport.png` 并点击按钮中心；若未出现传送按钮但出现 `MapCloseButton.png`，按上游 `ClickTpPoint` 语义抛出传送点未激活或不存在；若出现选项列表图标，则按上游 `MapChooseIconRoi` 识别十类图标、按 Y 扫描候选行，已支持同一图标模板多行候选，并在 OCR provider 可用时用图标右侧 200px、上下扩 8px 的 `ColorRangeAndOcr` 文本区域过滤空文本/单字文本，再点击首个有效行。点击后等待 `GoTeleport` 出现并点击，并按上游 `WaitForElementDisappear` 语义在按钮仍可见时重试点击直到消失或达到 6 次重试。传送点击后已按上游 `WaitForTeleportCompletion` 接入第一层主界面完成轮询：先等待配置的加载间隔，再循环截图识别 Common/Element `PaimonMenuRo`；有 OCR provider 时继续按上游 `Bv.IsInRevivePrompt` 检查 AutoFight `ConfirmRa` 和上半屏 OCR 的 `复苏`/`Revive`，避免复苏提示被误当主界面；若仍看到 `GoTeleport` 则容错补点一次，超时保持上游式非抛错。JS forced teleport replay 与 Pathing backend 已把可用的 PaddleOCR provider 接到该过滤路径；未接截图或所有分支都未识别时才退回原来的交互键兜底。当前还未覆盖 HDR 阈值切换
- ✅ 真实 `wine — 原神` 大地图 dry-run 验证通过：2026-07-03 `RealGenshinBigMapVerificationTests.openBigMapSkipsMapHotkeyWhenRealWindowAlreadyInBigMapUI` 在当前大地图窗口下调用 `openBigMap()`，input handler 记录到 `actions: []`，证明不会发送 `M` 或其它输入
- ✅ JS `genshin.*` 命令已新增 AppState 层 record-then-replay：`BGIJSScriptRunner` 继续记录 typed `BGIJSScriptGenshinCommand`，`BGIJSScriptGenshinCommandReplayer` 会把 `genshin.Tp(x, y, mapName, true)` 串到 `BGIBigMapInteractionService`，统一经过 `InputSafetyGate`；`SetBigMapZoomLevel(level)` 已按上游 `TpTask.AdjustMapZoomLevel(double,double)` 接入同一大地图服务，先识别当前 1.0...6.0 zoomLevel，再按 `ZoomButtonX=47`、`ZoomStartY=468`、`ZoomEndY=612` 拖动缩放条；`MoveMapTo` / `MoveIndependentMapTo` 在注入 provider 后可执行同款拖图循环；`ReturnMainUi` / `returnMainUi()` 已接入第一层 `BGIReturnMainUIService`，按上游 `ReturnMainUiTask` 先识别主界面，未回到主界面时最多 8 次按 Esc 并等待 900ms，最后补 Enter/Esc 兜底；`ChooseTalkOption(text, skipTimes, isOrange)` 已接入第一层 `BGIChooseTalkOptionService`，按上游 `ChooseTalkOptionTask.SingleSelectText` 先用 `AutoSkip.DisabledUiButtonRo` 复刻 `Bv.WaitAndSkipForTalkUi` 对话 UI 等待，再查找 `AutoSkip.OptionIconRo`、推导右侧 OCR 选项区域、没出现选项时按 Space 跳过、命中文本后点击 OCR 行，并用同款 HSV 阈值过滤橙色选项；`SetTime(hour, minute, skip)` 已接入第一层 `BGISetTimeService`，按上游 `SetTimeTask` 回主界面、Esc 打开派蒙菜单、点击 1080p `(50,700)` 时间入口、用同款钟盘中心/半径/角度公式执行三次小半径点击和一次拖动、点击 `(1500,1000)` 确认，并在非 skip 路径等待 `Common/Element/page_close_white.png` 后回主界面；`Relogin()` 已接入第一层 `BGIExitAndReloginService`，按上游 `ExitAndReloginJob` 用 `AutoWood.MenuBagRo` 反复 Esc 等菜单、点击左下退出、用 `AutoWood.ConfirmRo` 点击确认并等待消失、等待 `AutoWood.EnterGameRo` 出现后点击 1080p `(955,666)` 直到消失，最后等待 Paimon 主界面；`AutoFishing(policy)` 已接入第一层 `BGIAutoFishingService`，按 F 键进入钓鱼模式并通过退出按钮模板检测进退，完整 YOLO 鱼群检测、ONNX 饵料分类和张力条实时追踪仍待移植。`tp.json` 最近点/神像数据已可加载，但非 `force` 的 `Tp`、`TpToStatueOfTheSeven` 仍保持 pending，因为上游 `TpTask.TpOnce` 还依赖 `GetBigMapRect`、`GetPositionFromBigMap`、地区切换和视口内点击换算，避免只按全图比例估算点击而伪装已完成
- ✅ 本机真实 `bettergi-scripts-list` 存在时会执行 catalog smoke test，验证 repo.json 和 JS manifest 扫描可用
- ⚠️ JS runtime 仍需把 AutoFishing 等 typed `genshin.*` command 继续接到真实任务实现，把 `SwitchParty` 继续补完整 OCR 队名匹配和逐页滚动查找，把 `ChooseTalkOption` 继续补齐完整 AutoSkip 对话态分支与语音等待，把 `SetTime` 继续用真实游戏窗口校准点击入口和动画跳过成功率，把 `Relogin` 继续补齐上游 `Login3rdParty` / B 服第三方登录分支和真实登录页长等待验证，把 `BGIPathingNavigationBackend` 补完上游 `TpTask.GetBigMapRect`、`MoveMapTo` 前置国家/区域切换、最近传送点查找、`ClickTpPoint` HDR 阈值、完整移动异常处理和 action handler；`ColorMatch` / `Detect` 等非 `ImageRegion` 兼容路径需等具体上游调用点再接。HDR 阈值切换当前按 macOS/YAAGL 真实表现有意暂停：YAAGL HDR 采集会明显过曝，游戏内容几乎不可读，先保持非 HDR 主链路

---

## 六、地图与寻路

### 6.1 地图定位

**流程**: 小地图裁剪（固定 ROI）→ 模板匹配 Tile → 坐标换算 → 屏幕坐标

**原工程序文件**:
- `GameTask/Common/Map/Maps/` — 各地图实现（Teyvat/Chasm/Enkanomiya 等 6 张地图）
- `GameTask/Common/Map/MiniMap/MiniMapPreprocessor.cs`
- `GameTask/Common/Map/CameraOrientation.cs`

**macOS 当前进度**:
- ✅ `BGIMiniMapExtractor` 已按上游 `AutoTrackPathTask.GetMiniMapMat` / `MiniMapMatchConfig` 固化关键尺寸：派蒙图标 `38×40`、小地图 viewport `210×210`、中心原始小地图 `156×156`、粗匹配 `52`、精匹配 `260`
- ✅ 已迁移上游 `GameTask/Common/Element/Assets/1920x1080/paimon_menu.png`，`BGIMiniMapPaimonLocator` 可在左上 1/4 捕获区域定位 Paimon 模板，并把精确左上角传给小地图裁剪
- ✅ fallback 小地图裁剪已支持智能识别 Quartz 截图是否带 macOS 标题栏；识别到窗口装饰时仅对 fallback ROI 下移，Paimon 模板匹配给出精确坐标时不叠加补偿
- ✅ `BGIMiniMapPreprocessor` 已移植上游 `MaskCalculator.Process1` / `CreateIconMask` 基础规则：按通道最大/最小值识别小地图 UI 图标遮罩，并生成圆形有效区域与 usable mask
- ✅ `BGIMiniMapOrientationEstimator` 已按上游 `CameraOrientationCalculator.PredictRotation` 建立 Swift 基线实现：极坐标环形采样、alpha mask、Hue/Luma 双直方图和角度投票均已接入，真实窗口可输出角度与置信度诊断
- ✅ `MaskCalculator.Process2` 已有 Swift 基线：按朝向角生成扇区 alpha 处理图、背景 seed/扩展 mask 和最终匹配 mask，可输出后续 `MatchContext` 需要的 processed 156 图与 final mask
- ✅ `BGIMiniMapMatchContext` / `BGIMiniMapTemplateLayer` 已建立 Swift 粗/精匹配基线：可把 processed 小地图生成 `52×52` 彩色粗匹配模板、`260×260` 灰度精匹配模板和对应 mask，并完成上游地图 JSON 字段解析、tile 局部匹配、地图像素点与世界坐标互转的合成测试
- ✅ `BGIMiniMapLocalizationService` 已接入运行时 `Assets/Map/<Region>` 地图资源，并按上游 `BaseMapLayerByTemplateMatch.LoadLayers` 语义递归读取所有 `*.json` layer 描述；本地匹配会先尝试上一 layer，失败后继续尝试其他 layer，精匹配使用粗匹配更新后的世界坐标
- ✅ `macgi-core` 已新增 `macgi_core_match_pixels`，Swift 侧 `RustPixelMatchBridge` 可直接用 `PixelImage` + mask 调 Rust 计算 masked sqdiff；`RustPixelMatchBridge.loadDefault()` 已支持 SwiftPM test helper 的非仓库 cwd，通过 `#filePath` 追加本地 repo-root dylib 候选，并保留 Swift fallback
- ✅ `macgi_core_match_pixels` 现带三级后端：启用 `opencv-match` feature 时优先走 Rust `opencv` crate / OpenCV `TM_CCORR` 相关图，按上游 `FastSqDiffMatcher` 公式计算 `sum(source²*mask) - 2*corr(source, maskedTemplate) + sum(template²*mask)`；未启用或 OpenCV 失败时回落 RustFFT，再回落直接 masked sqdiff + lower-bound 剪枝。测试覆盖 OpenCV/FFT 与直接 sqdiff 一致、下界不超过真实 sqdiff、最佳点不在采样网格时仍能找回
- ✅ `macgi_core_match_u8_pixels` 已接入并由 Swift `RustPixelMatchBridge` 优先使用：`PixelImage` 保留 `[Double]` 兼容字段，同时缓存 `[UInt8]` 热路径像素，地图匹配跨 FFI 不再必须传输 8 字节/通道 Double 源图；旧 `macgi_core_match_pixels` 仍作为 dylib 兼容 fallback
- ✅ OpenCV 本机构建已验证：`opencv 0.99.0` 固定版本，默认 Cargo feature 不启用以免 CI/无 OpenCV 环境失败；开发机可用 `OPENCV_LINK_LIBS=opencv_core,opencv_imgproc OPENCV_LINK_PATHS=/opt/homebrew/opt/opencv/lib OPENCV_INCLUDE_PATHS=/opt/homebrew/opt/opencv/include/opencv4 cargo build --lib --features opencv-match` 构建最小链接 dylib，避免 Homebrew `pkg-config opencv4` 默认拉入全部 OpenCV 模块
- ✅ `BGIMiniMapLocalizationService` 全局粗匹配已优先扫描主地图 `MapBack*` layer，并支持达到全局成功阈值时早停；低于阈值仍继续扫描后续 layer。2026-07-03 已把地图 layer 加载拆成 descriptor / coarse layer / full layer 三级缓存，首次 global rough 只按需解码粗匹配彩图，命中后再加载对应精匹配灰度图，避免冷启动时无差别解码 292 个 Teyvat layer
- ✅ 真实 `wine — 原神` 窗口验证通过：`MACGI_RUN_REAL_WINDOW_TESTS=1 swift test --filter RealGenshinMiniMapVerificationTests` 可输出完整帧、Paimon 命中置信度、`210×210` viewport、`156×156` 小地图、icon/usable/final mask、processed 图和朝向诊断；2026-07-03 实测窗口 `960×572`、Paimon confidence `0.830`、orientation confidence `0.531`
- ✅ 真实 `wine — 原神` full diagnostic 在 OpenCV feature dylib 下已跑通：2026-07-03 实测总耗时 `73.5s`，`rough=2.57s`、`exact=15ms`，定位到 `City_102 (蒙德城)`，粗匹配 confidence `0.969`，精匹配 confidence `0.954`
- ✅ lazy layer 后真实 `wine — 原神` full diagnostic 复测：2026-07-03 总耗时 `5.27s`，`layer=13.7ms`、`rough=3.90s`、`exact=309ms`，仍定位到 `City_102 (蒙德城)`，粗匹配 confidence `0.970`，精匹配 confidence `0.954`
- ✅ u8 FFI 后真实 `wine — 原神` full diagnostic 复测：2026-07-03 总耗时 `5.12s`，`layer=12.6ms`、`rough=3.72s`、`exact=332ms`，仍定位到 `City_102 (蒙德城)`，粗匹配 confidence `0.969`，精匹配 confidence `0.954`
- ⚠️ `CameraOrientationCalculator` / `MaskCalculator.Process2` 数值仍需与上游 OpenCV/Rust 对齐；OpenCV 后端已把 matcher 热点降到秒级，lazy layer 已解决首帧 70 秒级全量解码，u8 FFI 已消除 Double 跨边界热路径。当前主要瓶颈是首次 global rough 仍需按序为多个 coarse layer 临时构造 OpenCV Mat；下一步应把 layer cache 下沉到 Rust/OpenCV，持久化 source Mat / source² Mat / split channel，避免每次 match 重建

**地图数据**: `BetterGI.Assets.Map` NuGet 包（`webp/png` tile + 多个 `*_info.json` layer 描述）

### 6.2 路径执行

**文件**: `GameTask/AutoPathing/PathExecutor.cs`

**流程**: 加载路径点 → 当前位置 → 方向计算 → WASD 移动 → 到达检测

**依赖**: 地图定位 + 输入模拟（WASD sustained + mouse aim）

### 6.3 传送系统

**文件**: `GameTask/AutoPathing/TpTask.cs`

**流程**: 打开大地图 → 搜索目标 → 点击传送点 → 确认

---

## 七、配置系统

| 配置项 | 原实现 | macOS |
|---|---|---|
| AllConfig (40+ 子配置) | C# class → JSON | 完全可移植，换 Swift Codable |
| 热更新检测 | CommunityToolkit.Mvvm | 换 SwiftUI @Published / Combine |
| 用户数据目录 | `%AppData%` | `~/Library/Application Support/betterGI-mac/` |

### 关键配置项清单:

```
CommonConfig        — 通用设置（截图模式、AI 设备、触发器间隔）
AutoPickConfig      — 自动拾取（白名单/黑名单、拾取延迟）
AutoSkipConfig      — 自动剧情（选项策略、提交物品、邀约策略、语音等待）
AutoFishingConfig   — 自动钓鱼（抛竿策略、鱼饵）
AutoEatConfig       — 自动吃药（血量阈值、食物选择）
MapMaskConfig       — 地图遮罩（显示的标点类型）
SkillCdConfig       — 技能冷却（显示位置、透明度）
KeyBindingsConfig   — 按键映射（所有游戏操作 → 按键）
HotKeyConfig        — BetterGI 自身快捷键
NotificationConfig  — 通知设置
OneDragonFlowConfig — 一条龙任务列表
ScriptConfig        — 脚本目录/仓库
```

---

## 八、一条龙（每日流程）

### 任务列表:
1. 自动战斗（秘境/地脉）→ 合成树脂 → 领取每日奖励
2. 领取探索派遣 → 领取纪行 → 领取长效历练点
3. 领取邮件 → 地脉花 → 千星奇域 → 重新登录

### 执行模式:
- 顺序执行，每步 try-catch + 通知
- 可配置每步启用/禁用
- 完成后可关机/睡眠

---

## 九、移植优先级矩阵

### 🔴 P0 — 下个 session 就做（"Hello OCR"）

| 组件 | 理由 |
|---|---|
| **ScreenCaptureKit 截图** | 一切识别的前提 |
| **WindowInfo 枚举** (CGWindowListCopyWindowInfo) | 替代 mock window |
| **PaddleOCR ONNX 集成** | 文字识别是核心（剧情/拾取/选项/名字） |
| **CGEvent 键盘输入（dry-run first）** | 按键链路 |
| **AutoSkip 极简版** | 跳过按钮 + Press F — 最简完整闭环 |

### 🟡 P1 — 下一个阶段

| 组件 | 理由 |
|---|---|
| **AutoPick 完整版** | F 键模板匹配 + OCR 物品名 + 过滤 |
| **模板匹配引擎** | 所有 trigger 的基础 |
| **AutoSkip 完整版** | 选项选择、物品提交、邀约 |
| **VAD 语音检测** | AutoSkip 体验关键 |
| **配置系统（JSON → Codable）** | 持久化用户设置 |
| **地图定位基础版** | 小地图 → 坐标 |

### 🟢 P2 — 进阶功能

| 组件 |
|---|
| **AutoFishing** |
| **AutoEat** |
| **YOLO 目标检测** |
| **AutoDomain (战斗)** |
| **地图遮罩渲染** |
| **技能冷却** |

### ⚪ P3 — 完整体验

| 组件 |
|---|
| **JS 脚本引擎** |
| **一条龙流程** |
| **寻路系统** |
| **Boss 讨伐 / 地脉花 / 木材** |
| **通知系统** |
| **快捷键系统** |
| **录制回放** |

---

## 十、当前代码准备状态

| 已完成 | 待实现 |
|---|---|
| ✅ SwiftUI UI 原型（12 个页面） | ❌ YOLO / VAD 模型接入 |
| ✅ HUD NSPanel（透明浮窗） | ❌ 最终 OpenCV 模板匹配后端 |
| ✅ `WindowInfo` 模型（CGWindowID/PID/frame） | ❌ Solo Task / Script 引擎迁移 |
| ✅ `CGWindowListCopyWindowInfo` → `[WindowInfo]` | ❌ 所有 Trigger 完整实现 |
| ✅ `ScreenCaptureKitFrameProvider` + Quartz fallback | ❌ 配置持久化 |
| ✅ 真实 `wine — 原神` Quartz 截图验证 | ❌ 地图 tile 数据迁移 |
| ✅ `CapturedFrame` / `CaptureImageFrame` | ❌ 全量 ONNX 模型下载/嵌入（YOLO/VAD/多语言仍缺真实资源） |
| ✅ `NormalizedROI` + `clampedPixelRect` | ❌ 全量模板 PNG 复制（当前仅 P0 子集） |
| ✅ `OCRResult` / `PaddleOCR` ONNX Runtime | ❌ 真实输入默认启用前的端到端验收 |
| ✅ `RecognitionObject` / `RecognitionTypes` | |
| ✅ Swift 侧模板匹配引擎（单目标 + 多目标基础） | |
| ✅ Rust 像素模板匹配后端（单目标 + 多目标基础） | |
| ✅ Swift → Rust 模板识别 FFI 调用链 | |
| ✅ `InputAction` / `KeyCode` / `ModifierFlags` | |
| ✅ CGEvent 输入模拟 + foreground/safety guard | |
| ✅ `InputSafetyGate`（三态 dryRun/allow/blocked） | |
| ✅ `InputTargetResolver`（observation rect → 屏幕点击点） | |
| ✅ Task trigger loop 原型 | |
| ✅ MockServices 协议契约 | |
| ✅ shared/macgi_core.h (C FFI) | |
| ✅ RustCoreBridge + mock fallback | |
| ✅ 首次启动资源目录骨架 + 外部资源包 manifest | |
| ✅ `.nupkg`/contentFiles 资源包安装器 | |
| ✅ 首次启动资源下载/cache/bootstrapper 骨架 | |
| ✅ `bettergi-scripts-list` Git release 分支浅克隆/更新器 | |
| ✅ `Application Support` / 用户脚本目录 / JS `saved_files` 目录 symlink 外置盘适配 | |
| ✅ `repo.json` / JS `manifest.json` / `settings.json` catalog 解析 | |
| ✅ YOLO 模型注册 + 后处理 NMS/坐标缩放底座 | |

---

## 十一、模型文件清单（需从 upstream 复制）

### ONNX 模型（来自 `BetterGI.Assets.Model` NuGet contentFiles，可嵌入或首次启动下载）
```
Assets/Model/PaddleOCR/Det/V4/PP-OCRv4_mobile_det_infer/slim.onnx        — 已嵌入
Assets/Model/PaddleOCR/Rec/V4/PP-OCRv4_mobile_rec_infer/slim.onnx        — 已嵌入
Assets/Model/PaddleOCR/Rec/V4/en_PP-OCRv4_mobile_rec_infer/slim.onnx     — 已嵌入
Assets/Model/PaddleOCR/Det/V5/PP-OCRv5_mobile_det_infer/slim.onnx        — 待迁移/下载
Assets/Model/PaddleOCR/Rec/V5/PP-OCRv5_mobile_rec_infer/slim.onnx
Assets/Model/PaddleOCR/Rec/V5/latin_PP-OCRv5_mobile_rec_infer/slim.onnx
Assets/Model/PaddleOCR/Rec/V5/eslav_PP-OCRv5_mobile_rec_infer/slim.onnx
Assets/Model/PaddleOCR/Rec/V5/korean_PP-OCRv5_mobile_rec_infer/slim.onnx
Assets/Model/Fish/bgi_fish.onnx
Assets/Model/Domain/bgi_tree.onnx
Assets/Model/World/bgi_world.onnx
Assets/Model/Mine/bgi_mine.onnx
Assets/Model/Common/avatar_side_classify_sim.onnx
Assets/Model/Common/q_classify_sim.onnx
Assets/Model/Vad/silero_vad.onnx
Assets/Model/Yap/model_training.onnx
```

### 模板图片 (~5MB)
```
GameTask/AutoPick/Assets/1920x1080/*.png
GameTask/AutoSkip/Assets/1920x1080/*.png
GameTask/AutoFishing/Assets/1920x1080/*.png
GameTask/AutoEat/Assets/1920x1080/*.png
GameTask/MapMask/Assets/*.png
```

### 地图数据（~200MB）
```
BetterGI.Assets.Map NuGet 包 → PNG tile 文件
```

### 配置文件
```
GameTask/AutoFight/Config/combat_avatar.json  — 角色战斗数据库
Assets/GameResource/word_list.json            — 物品名词典
```

---

## 十二、脚本仓库 — 运行时从 Git 分发

### 12.1 架构

脚本 **不随源码编译**。通过 Git 浅克隆在首次启动时下载。

**中央仓库**: `bettergi-scripts-list`（三个镜像）:
| 渠道 | URL |
|---|---|
| CNB | `https://cnb.cool/bettergi/bettergi-scripts-list` |
| GitCode | `https://gitcode.com/huiyadanli/bettergi-scripts-list` |
| GitHub | `https://github.com/babalae/bettergi-scripts-list` |

### 12.2 仓库结构

```
bettergi-scripts-list/
  repo.json          — 索引文件（脚本列表+元数据）
  repo/
    js/              — JS 脚本
    pathing/         — 路径脚本（录制回放）
    combat/          — 战斗策略脚本
    tcg/             — 七圣召唤脚本
```

### 12.3 检出映射

脚本从仓库检出到用户目录的映射：

| 仓库路径 | 本地目录 |
|---|---|
| `js/` | `User/JsScript/` |
| `pathing/` | `User/AutoPathing/` |
| `combat/` | `User/AutoFight/` |
| `tcg/` | `User/AutoGeniusInvokation/` |

### 12.3.1 已迁移 User 目录兼容目标

当前本机 `~/Library/Application Support/betterGI-mac/User` 已放入从 Windows BetterGI 复制来的真实订阅脚本与配置，这是后续移植的兼容验收目标，不能只按仓库 fixture 或截图假设行为：

- `User/JsScript/`：真实 JS 项目，含 `manifest.json`、`settings.json`、`main.js`、`assets/`、`packages/`、`saved_files` 目录等
- `User/AutoPathing/`：真实路线树，当前样本约 4978 个 `.json`，含 `icon.ico` / `desktop.ini` 等 Windows 元数据；列表阶段应像上游 `FileTreeNodeHelper.LoadDirectory` 一样只建立树，不批量 decode 所有路线
- `User/AutoFight/`：真实战斗策略 `.txt`，子目录相对名如 `群友分享/万能战斗策略...` 必须保留，匹配上游 `AutoFightViewModel.LoadCustomScript`
- `User/AutoGeniusInvokation/`：真实七圣召唤策略 `.txt`
- `User/ScriptGroup/`：调度器配置；`狗粮+锄地.json` 是当前最重要的综合样本，连续调用 `WeeklyThousandStarRealm`、`AutoHoeingOneDragon`、`AAA-Artifacts-Bulk-Supply`、`AbundantOre`、`ExitGameMultipleMode` 等 JS，并依赖 `projects[].jsScriptSettingsObject`
- `User/OneDragon/`：一条龙配置，如 `默认配置.json`
- `User/Cache/MemoryFileCache/`、`User/Temp/`、`User/KeyMouseScript/`：需保留上游目录位置，避免后续脚本假设路径时不兼容

Swift 侧新增 `BGIUserScriptCatalogLoader` 作为真实 `User` 树索引入口，扫描 JS 项目、路线树、战斗/七圣召唤策略、KeyMouse、ScriptGroup 和 OneDragon 配置。真实 `User` 目录存在时会执行 smoke test；`ScriptGroup/狗粮+锄地.json` 存在时会单独解码，验证 `jsScriptSettingsObject` 不丢失。

`AppState` 启动时会通过 `BGIUserScriptCatalogLoader.loadScriptGroups()` 读取真实 `User/ScriptGroup/*.json` 并提供给 `SchedulerPage`；无真实配置时才回退 mock 默认组。调度器侧栏已展示真实配置组并可切换选中组，普通“运行”路径按上游 `OnStartScriptGroupAsync()` 只运行当前选中组，避免误触全部配置组；多配置组执行后续应单独对齐上游 `StartGroups(...)` 入口。

### 12.4 订阅机制

- 用户通过 WebView 界面浏览仓库并"订阅"感兴趣的脚本
- 订阅数据存于 `User/Subscriptions/{repoName}.json`
- 启动时自动拉取更新：`ScriptRepoUpdater.AutoUpdateSubscribedScripts()`
- 支持剪贴板导入 `bettergi://script?import=` URL

**当前 Swift 侧落地**:
- ✅ `BGIScriptRepositoryUpdater` 在 clone/fetch 后写出 `Repos/{repoName}/repo_updated.json`，优先继承旧 `repo_updated.json`，否则用旧 `repo.json` 对比
- ✅ `BGIScriptRepositoryUpdateMarkerGenerator` 复刻上游 `AddUpdateMarkersToNewRepo()` 的核心语义：目录重合度低于 0.5 视为不同仓库，不继承旧标记；否则保留旧 `hasUpdate`，按 `lastUpdated` 和新增节点打标，并将叶子更新冒泡到父节点
- ✅ `BGIScriptSubscriptionStore` 读写 repo-scoped JSON；坏 JSON、空文件、缺文件均按空订阅处理，空订阅会删除文件
- ✅ `BGIScriptImportRequest` 按上游 `ParseUri()` 兼容 `bettergi://script?import=`：先 base64 解码，再 URL decode，再解析 JSON string array
- ✅ 导入或更新订阅时会把 `js`、`pathing`、`combat`、`tcg` 这类裸顶层路径展开为仓库直接子目录，避免覆盖整个 `User/JsScript` 等用户根目录
- ✅ 订阅清理会过滤危险路径、未知 root、本地已不存在目标，并在所有直接子节点已订阅时压缩回父路径，保持和上游 WebView 订阅语义一致
- ✅ `updateSubscribedScripts()` 可选择先拉取中央 Git 仓库，再通过 symlink-preserving checkout 更新已订阅路径
- ✅ `BGIScriptRepositoryWebBridge` 已实现 `GetRepoJson`、`GetSubscribedScriptPaths`、`GetFile`、`ImportUri`、`UpdateSubscribed`、`ClearUpdate` 对应的 Swift 服务层语义，并对仓库文件读取做扩展名白名单和路径越界防护
- ✅ JS 脚本 checkout 已在替换前备份 `saved_files` 指定的文件/目录/通配符匹配结果，替换后恢复到用户脚本目录
- ✅ JS 脚本依赖解析已扫描本地 `.js` 文件中的 `import`/`export`/`require`，将仓库根目录 `packages/...` 文件复制到脚本本地 `packages/`，并递归处理 packages 内部相对 JS import

### 12.5 macOS 移植建议

- **Git 操作**: 原项目用 `LibGit2Sharp`。macOS 可直接调 `git` CLI（系统自带），或嵌入 `libgit2` C 库
- **WebView 界面**: 原项目用 WebView2。macOS 用 WKWebView 包裹同一套 HTML frontend，底层 bridge 可复用 `BGIScriptRepositoryWebBridge`
- **仓库镜像**: 三个镜像 URL 可直接复用，或增设 Gitee/自建镜像
- **目录结构**: macOS 用户目录应映射到 `~/Library/Application Support/betterGI-mac/User/`

**当前 macOS 代码状态**:
- ✅ `BGIScriptRepositoryUpdater` 已使用 `/usr/bin/git` 支持 `release` 分支浅克隆、已有仓库 fetch/reset、镜像失败回退
- ✅ 默认渠道与上游 `RepoChannels` 一致：CNB → GitCode → GitHub
- ✅ 已验证 `repo/js`、`repo/pathing`、`repo/combat`、`repo/tcg` 到 `User/JsScript`、`User/AutoPathing`、`User/AutoFight`、`User/AutoGeniusInvokation` 的映射
- ✅ `BGIRuntimeResourceStore` 目录骨架已补齐上游常用 `User/KeyMouseScript`、`User/ScriptGroup`、`User/OneDragon`、`User/Temp`、`User/Cache/MemoryFileCache`
- ✅ `BGIUserScriptCatalogLoader` 已按真实 Windows BetterGI `User` 目录扫描已安装脚本/策略/路线/调度器/一条龙配置，并在本机真实迁移目录存在时 smoke test
- ✅ 调度器 `BGIScriptGroupProject` 已兼容上游 `jsScriptSettingsObject`，Swift 内部执行仍使用 JSON 字符串，但写文件保持对象字段；本机 `User/ScriptGroup/狗粮+锄地.json` 会作为综合 JS 链式调度样本解码验证
- ✅ `AppState` 已在启动时加载真实 `User/ScriptGroup` 到 `SchedulerPage`，侧栏展示真实配置组并允许切换；普通运行入口只执行当前选中配置组，匹配上游 `OnStartScriptGroupAsync()`
- ✅ 本机已将真实 `bettergi-scripts-list` 克隆到 `~/Library/Application Support/betterGI-mac/Repos/bettergi-scripts-list`
- ✅ checkout 会保留 `User/JsScript` 等 symlink 目录本身，只替换 resolved target 下的内容，适配 `/Volumes/Data/Library/Application Support/...` 这类外置盘布局
- ✅ JS `saved_files` 恢复会保留已保存目录 symlink 本体，避免把外置盘链接展开成普通目录
- ✅ `BGIScriptRepositoryCatalogLoader` 已解析 `repo.json` 递归索引、JS `manifest.json`、JS `settings.json`，并对真实本机 clone 做 smoke test
- ✅ `BGIScriptSubscriptionStore` 已实现订阅 JSON、import URL、顶层路径展开、订阅路径清理和订阅 checkout/update 核心
- ✅ `repo_updated.json` 更新标记已接入 Git clone/fetch 更新器，并覆盖目录重合度、上次标记继承、新增/更新时间递归打标
- ✅ RepoWebBridge 服务层已实现，可供后续 WKWebView 绑定
- ✅ JS `saved_files` 备份恢复与 `packages/` 依赖解析已接入 checkout/update 流程
- ✅ JS runtime 第一层已接入 JavaScriptCore，覆盖已安装脚本加载、PackageDocumentLoader 风格模块/资源解析、`settings` 注入、typed host command、`genshin.*` typed command/result 边界、`BvPage.Keyboard` / `Mouse` 输入对象、支持输入命令到 `CGEventInputDispatcher` 的适配入口、`captureGameRegion().Ocr()` / `Find()` / `FindMulti()` 的截图/OCR/OcrMatch/ColorRangeAndOcr/template provider 边界、上游不支持类型拦截、OCR Find/FindMulti 返回形态、`BvPage` / `BvLocator` OCR 兼容入口、`BvLocator` template 单目标 FindAll、`BvLocator` 等待/重试/点击链式语义与 `ClickUntilDisappears` fresh-locator 语义、`BvImage` template locator provider/default Swift matcher 边界、`BGIJSScriptTaskExecutor` 已安装脚本执行入口、AppState/JS 页面手动运行入口，以及参考上游 `ScriptGroupProject` / `RunMulti` 的 scheduler → JS/KeyMouse/Shell/Pathing 第一层绑定
- ⚠️ WKWebView 仓库浏览容器/UI、Pathing 的完整上游导航细节、OpenCV 图像对象、真实 `genshin.*` async/immediate 动作仍待移植；`ColorMatch` / `Detect` 继续按上游实际使用点补齐

---

## 十三、首次启动 → 运行时下载流程

### 13.1 编译时随源码发布（不需要下载）

| 内容 | 原 Windows 方式 | macOS 方式 |
|---|---|---|
| ONNX 模型 (~50MB) | NuGet 包 `BetterGI.Assets.Model` | 嵌入 `Bundle.module` Resources，或首次启动从 GitHub Release 下载 |
| 地图 tile (~200MB) | NuGet 包 `BetterGI.Assets.Map` | 同上 |
| 模板图片 (~5MB) | 源码 `GameTask/*/Assets/` | 嵌入 `Bundle.module` Resources |
| 字体 (.ttf) | WPF Resource 内嵌 | 已嵌入 `FontRegistry`（MiSans + Fgi） |
| 用户配置模板 | `User/` 空目录结构 | Swift Codable 生成默认值 |
| 角色战斗数据库 | `combat_avatar.json` | 嵌入或首次下载 |
| 物品名词典 | `word_list.json` | 嵌入或首次下载 |
| 其他资源 | NuGet 包 `BetterGI.Assets.Other` | 待核对 package 内容后决定嵌入或首次下载 |

### 13.2 首次启动时下载（运行时）

| 内容 | 来源 | 触发 |
|---|---|---|
| **脚本仓库** | Git 浅克隆 (CNB/GitCode/GitHub) | 启动时 `AutoUpdateSubscribedScripts()` |
| **i18n 语言文件** | GitHub raw / CNB raw | 用户切换非中文语言时 |
| **地图标记点** | HoYoLab / Mihoyo API | 运行时按需 |
| **地图图标** | HTTP + 20 天本地缓存 | 运行时按需 |
| **程序更新** | OSS / MirrorChyan | 启动时检查 |
| **兑换码公告** | CNB raw | 启动时检查 |

### 13.3 macOS 首次启动流程设计建议

```
App 启动
  → 创建 ~/Library/Application Support/betterGI-mac/
    → User/ 子目录 (JsScript/, AutoPathing/, AutoFight/, etc.)
    → Repos/ 子目录
    → Assets/ 子目录 (首次下载的 Model/Map/Other 资源)
    → Cache/Downloads/ 子目录 (首次启动资源包缓存)
    → Cache/Model/ 子目录 (ONNX 优化缓存)
    → log/ 子目录

  → 支持将 ~/Library/Application Support/betterGI-mac 或其子目录 symlink 到外置盘
    → 例如 /Volumes/Data/Library/Application Support/betterGI-mac
    → 创建目录和脚本 checkout 均保留 symlink 本身

  → 如果 Assets/Model/ 目录为空
    → `BGIExternalResourceBootstrapper` 从 NuGet flat-container / 后续镜像下载 ONNX 模型包 (~50MB)
      https://api.nuget.org/v3-flatcontainer/bettergi.assets.model/1.0.24/bettergi.assets.model.1.0.24.nupkg
    → `BGIExternalResourceInstaller` 解压 `.nupkg`/zip
    → 从 `contentFiles/any/any/Assets/Model/` 安装到 Assets/Model/

  → 如果 Assets/Map/ 目录为空
    → `BGIExternalResourceBootstrapper` 从 NuGet flat-container / 后续镜像下载地图数据包 (~200MB)
      https://api.nuget.org/v3-flatcontainer/bettergi.assets.map/1.0.19/bettergi.assets.map.1.0.19.nupkg
    → 或提示用户可选下载
    → 从 `contentFiles/any/any/Assets/Map/` 安装到 Assets/Map/

  → 脚本仓库首次克隆
    → `BGIScriptRepositoryUpdater` 按 CNB/GitCode/GitHub 顺序尝试
    → `git clone --depth 1 --branch release --single-branch` bettergi-scripts-list → Repos/bettergi-scripts-list
    → clone/fetch 后生成 Repos/bettergi-scripts-list/repo_updated.json 更新标记
    → `BGIScriptSubscriptionStore` 读写 User/Subscriptions/{repoName}.json
    → 用户订阅路径后续从 repo/js、repo/pathing、repo/combat、repo/tcg checkout 到 User/

  → 检查程序更新
```
