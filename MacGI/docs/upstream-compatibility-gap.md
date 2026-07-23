# 上游兼容性缺口分析

> 对照上游 BetterGI v0.61.3-alpha.1，评估 BetterGI-mac 当前代码与上游的潜在不兼容处。
> 目标：使 macOS 版能直接复用上游 ONNX 模型、模板 PNG、脚本和地图数据。

---

## 分析范围与免责

以下分析基于源码对比，非集成测试结果。标记 ⚠️ 的项表示存在已知差异，标记 🔴 表示当前无条件使用上游资源，标记 ✅ 表示已验证兼容。

---

## 一、ONNX 模型运行时层（可复用上游模型，但推理路径有差异）

| # | 差异项 | 上游 | macOS 当前 | 影响 |
|---|--------|------|-----------|------|
| 1.1 | **ONNX Runtime 版本** | `Microsoft.ML.OnnxRuntime.DirectML v1.21.0` | `onnxruntime-swift-package-manager v1.24.2` | ✅ ONNX 规范保证向下兼容，模型文件可直接复用 |
| 1.2 | **执行后端** | TensorRT → DirectML → CUDA → OpenVINO → CPU（GPU 加速 + 多级回退） | **纯 CPU**（`intraOpNumThreads=1`），无 GPU/ANe 后端 | ⚠️ 性能差异，不影响正确性。模型文件可直接复用，但推理延迟可能较高 |
| 1.3 | **模型缓存** | TensorRT engine cache（`*_ctx.onnx`）、optimized model cache | 无 | ⚠️ 不影响正确性。上游缓存文件不能直接用于 macOS |
| 1.4 | **图优化** | `OptimizedModelFilePath` 支持 | 无 | ⚠️ 不影响正确性 |

## 二、PaddleOCR 推理管线（可复用上游 ONNX 模型，预处理和后处理需对齐）

### 2.1 检测模型 (Det) 预处理

| 差异项 | 上游 | macOS 当前 | 兼容性 |
|--------|------|-----------|--------|
| 通道处理 | BGRA→BGR / GRAY→BGR | BGR 来自 CGImage（需验证通道序） | ⚠️ 需验证 |
| 长边缩放 | `MatResize(maxSize=960)`：等比缩放至长边 ≤ 960 | `maxLongSide: 960`，等比缩放 | ✅ 一致 |
| 32 倍数填充 | `CopyMakeBorder(0, padH, 0, padW)` 右下填充 | 零值填充分配 + 写入有效区域 | ✅ 等价 |
| 归一化公式 | `ConvertTo(bgr[i], CV_32F, 1/std[i], -mean[i]/(std[i]*scale))` 后 `BlobFromImage(scale)` = `(pixel*scale - mean) / std` | `(byte*scale - mean) / std` | ✅ 公式等价 |
| 参数值 | scale=1/255, mean=[0.485,0.456,0.406], std=[0.229,0.224,0.225] | 同一套参数 | ✅ 一致 |
| 通道序 | BGR（`swapRb=false`） | BGR 序写入 tensor | ✅ 一致 |

### 2.2 检测模型 (Det) 后处理 — 🔴 关键差异

| 差异项 | 上游 | macOS 当前 |
|--------|------|-----------|
| 轮廓检测 | OpenCV `FindContoursAsArray` + `MinAreaRect` → **旋转矩形**（带角度） | 纯 Swift 八邻域 BFS connected-components → **轴对齐矩形**（无角度） |
| 矩形膨胀 | `minEdge = min(w, h)` → 按 `UnclipRatio=2.0` 等比例扩展 w + h | 使用 `DetectionComponent` 的宽度和高度直接 expand |
| 评分方式 | `FillPoly` 创建 mask → `Mean(mask)` 区域平均 | `meanScore` 直接对连通域像素取平均值 |
| 排序方式 | Y 排序 → X 排序 | 同（先 Y 后 X，8px 容差） |

**影响评估**：
- 对水平排列的文字（原神 UI 大多数情况），轴对齐矩形足够
- 对旋转排列的文字（如某些 UI 倾斜标签），旋转矩形更准确
- 两者会对同一输入生成不同尺寸/角度的检测框，进而影响 Rec 模型的输入

### 2.3 识别模型 (Rec) 预处理

| 差异项 | 上游 | macOS 当前 | 兼容性 |
|--------|------|-----------|--------|
| 输入形状 | `OcrShape(3, 320, 48)`（batch 动态宽度） | `PaddleOCRImageShape(3, 320, 48)` | ✅ 一致 |
| 缩放逻辑 | 等比缩放到 H=48，W = ceil(48*ratio)，上限 320 | 等比缩放，上限 maxWidth（未指定时为 `unclampedWidth`） | ⚠️ 默认行为等价，但 macOS 有额外 `maxWidth` 参数可传入 |
| 归一化公式 | `CvDnn.BlobFromImage(resized, 2/255f, ..., Scalar(127.5,127.5,127.5))` = `(pixel - 127.5) / 127.5` | `(channel - 127.5) * 2.0 / 255.0` = same | ✅ 等价 |
| 批处理 | 最多 8 张图片批量推理，按宽度排序最小化填充 | 单张推理 | ⚠️ 不影响正确性 |
| 通道处理 | BGRA→BGR / GRAY→BGR | 使用 sRGB 色彩空间 + premultipliedLast + order32Big 重采样 | ⚠️ CGImage 渲染可能引入细微色彩差异 |

### 2.4 CTC 解码

| 差异项 | 上游 | macOS 当前 | 兼容性 |
|--------|------|-----------|--------|
| 解码算法 | 贪心 CTC 解码 + 空格/空白处理 | 贪心 CTC 解码 | ✅ 等价 |
| label 索引 | `index > 0 && <= N` → labels[index-1]; `index == N+1` → " " | 同一逻辑 | ✅ 一致 |
| 置信度 | `score / text.Length`（被接受的字符数） | `sum / acceptedCount` | ✅ 等价 |

### 2.5 字典文件 (inference.yml)

| 差异项 | 上游 | macOS 当前 | 兼容性 |
|--------|------|-----------|--------|
| 字典格式 | YAML 格式 `character_dict_path` | 可解析 inference.yml → 提取 char list | ✅ 可直接复用上游 inference.yml |
| 默认模型 | `V4Auto`（中文自动选 V4，英文 V4En，台繁/港繁 V5） | 默认 V4 中文 | ⚠️ macOS 缺少上游 `OcrFactory` 的多语言自动选择逻辑 |

## 三、YOLO 目标检测 — 🔴 未落实

| 状态 | 说明 |
|------|------|
| 模型注册 | ✅ `BGIOnnxModel` 已注册全部 4 个 YOLO 模型 + 2 个分类模型 |
| 后处理 | ✅ `YOLODetectionPostProcessor` 已实现 letterbox 还原、NMS、按类别分组 |
| 推理 session | 🔴 **未创建 ONNX session**，YOLO 模型无法进行推理 |
| label 元数据 | 🔴 未加载（BgiFish/BgiTree/BgiWorld/BgiMine 的类别名称和颜色） |

**影响**：目前无法复用上游 YOLO 模型完成任何实际检测任务（钓鱼、挖矿、世界物体检测）。

## 四、Silero VAD — 🔴 未落实

| 组件 | 状态 |
|------|------|
| 模型注册 | ✅ `BGIOnnxModel.sileroVad` 已注册 |
| ONNX session | 🔴 未创建 |
| 音频采集 | 🔴 上游用 WASAPI loopback，macOS 需 AVAudioEngine |

**影响**：AutoSkip 的语音等待功能无法使用。

## 五、模板匹配（可复用上游 PNG 模板）

### 5.1 模板图片素材

| 项目 | 路径 | 当前状态 |
|------|------|---------|
| AutoPick 模板 | `GameTask/AutoPick/Assets/1920x1080/*.png` | ✅ 部分嵌入 |
| AutoSkip 模板 | `GameTask/AutoSkip/Assets/1920x1080/*.png` | ✅ 部分嵌入（P0 子集） |
| AutoFishing 模板 | `GameTask/AutoFishing/Assets/1920x1080/*.png` | 🔴 未嵌入 |
| AutoEat 模板 | `GameTask/AutoEat/Assets/1920x1080/*.png` | 🔴 未嵌入 |
| MapMask 模板 | `GameTask/MapMask/Assets/*.png` | 🔴 未嵌入 |

### 5.2 模板匹配引擎差异

| 差异项 | 上游 | macOS 当前 | 兼容性 |
|--------|------|-----------|--------|
| 匹配引擎 | OpenCV `Cv2.MatchTemplate` | Rust `PixelTemplateMatcher`（自定义实现） | ⚠️ 数学上等价，但不同实现可能有浮点误差导致的分数差异 |
| MatchMode 支持 | TM_CCOEFF_NORMED / TM_CCORR_NORMED / TM_SQDIFF_NORMED | CCorrNormed / CCoeffNormed / SqDiff | ✅ 一一对应 |
| 多目标匹配 | `MatchOne/MatchMulti` + NMS 去重 | 支持 maxMatchCount + 基础 NMS | ⚠️ NMS 实现可能需要对比验证 |
| 性能 | OpenCV 优化（SIMD） | 纯 Rust（可能更慢） | ⚠️ 性能差异 |

### 5.3 模板缩放逻辑

| 差异项 | 上游 | macOS 当前 | 兼容性 |
|--------|------|-----------|--------|
| AssetScale 规则 | `min(1.0, frameWidth / 1920.0)`，2K/4K 不放大 | `min(1, frameWidth / 1920)` | ✅ 一致 |
| 按分辨率文件夹 | `1920x1080/` 目录按需 | 同 | ✅ 可复用上游路径结构 |

## 六、AutoSkip / AutoPick 触发器 — ⚠️ 部分落实

### 6.1 AutoSkip

| 功能 | 上游实现 | macOS 当前 |
|------|---------|-----------|
| 跳过按钮检测 | 模板匹配 `AutoSkipAssets` | ✅ Rust AutoSkip 已实现 Space 分支 |
| 对话框选项选择 | 模板匹配 + OCR + 文本匹配 | ✅ 已 dry-run 验证凯瑟琳帧 |
| 每日奖励/探索派遣 | 模板匹配 `DailyRewardIconRo` / `ExploreIconRo` | ✅ 已验证 |
| 弹出关闭 | 模板匹配 close 按钮 | 🔴 未实现 |
| 物品提交 | 模板匹配感叹号 + OCR | 🔴 未实现 |
| 邀约事件 | 模板匹配 orange/non-orange 选项 | 🔴 未实现 |
| 语音检测 | Silero VAD | 🔴 未实现 |

### 6.2 AutoPick

| 功能 | 上游实现 | macOS 当前 |
|------|---------|-----------|
| F 键模板匹配 | 模板匹配 F 图标 | ⚠️ 模板已嵌入，完整触发器未接入 |
| OCR 物品名过滤 | OCR → 白名单/黑名单 | 🔴 未实现 |
| 排除条件检测 | 对话气泡/设置/滚动条 | 🔴 未实现 |

## 七、JS 脚本引擎 — ⚠️ 部分落实

### 7.1 脚本执行环境

| 差异项 | 上游 | macOS 当前 | 影响 |
|--------|------|-----------|------|
| JS 引擎 | ClearScript.V8 (V8) | C# Core Host 使用 ClearScript V8 `osx-arm64` | ✅ 同一上游引擎 |
| 模块系统 | ClearScript CommonJS | C# Core Host 使用上游 PackageDocumentLoader | ✅ 由 Core 解析 |
| WebView | WebView2 | Swift 平台层使用 WKWebView | 🟡 平台实现不同 |
| HTML 遮罩 | WPF WebView2 overlay | Core `htmlMask` 合同 + Swift WKWebView 窗口/消息桥 | 🟡 待更多真实脚本验证 |

### 7.2 脚本 API 兼容性

| API | 上游实现 | macOS 当前 | 缺口 |
|-----|---------|-----------|------|
| `genshin.Tp(x, y)` | 大地图定位 + 传送 | ✅ typed command 已定义，真实后端未接入 | 🔴 |
| `genshin.GetPositionFromMap()` | 小地图模板匹配 | ✅ typed result 已定义，真实后端未接入 | 🔴 |
| `genshin.GetCameraOrientation()` | 小地图分析 | ✅ typed result 已定义，真实后端未接入 | 🔴 |
| `genshin.SwitchParty(name)` | 输入 + 识别 | ✅ typed command，真实后端未接入 | 🔴 |
| `genshin.AutoFishing()` | YOLO 钓鱼检测 | ⚠️ typed command，依赖 YOLO | 🔴 |
| `captureGameRegion().Find(Ocr)` | 截图 + OCR | ✅ 已接入 PaddleOCR | ✅ |
| `captureGameRegion().Find(Template)` | 模板匹配 | ✅ Swift + Rust 双引擎 | ✅ |
| `captureGameRegion().Find(ColorRangeAndOcr)` | 颜色遮罩 + OCR | ✅ 已接入 | ✅ |
| `captureGameRegion().Find(ColorMatch)` | 颜色匹配 | 🔴 不支持（显式报错） | ⚠️ |
| `captureGameRegion().Find(Detect)` | YOLO 检测 | 🔴 不支持（显式报错） | 🔴 |
| `RecognitionObject.OcrMatch(...)` | OCR + 文本匹配 | ✅ 已实现（合并文本/去空白/替换误识别） | ✅ |
| `RecognitionObject.ReplaceDictionary` | OCR 后处理替换字典 | ✅ 已实现 | ✅ |
| `BvLocator.WaitFor/Click/ClickUntilDisappears` | 等待/重试/点击链式语义 | ✅ 已实现 | ✅ |
| `BvImage` template locator | 模板图像定位 | ✅ Swift matcher fallback | ⚠️ 走 Swift 引擎，非 OpenCV |

## 八、配置系统

| 差异项 | 上游 | macOS 当前 | 兼容性 |
|--------|------|-----------|------|
| 配置格式 | C# 类 → JSON 持久化 | `AppState` @Published 属性，**无持久化** | 🔴 重启后设置丢失 |
| 配置模型 | 30+ 嵌套配置子对象 | 扁平化属性 | ⚠️ 无法直接复用上游 JSON 配置模板 |
| 键位绑定 | `KeyBindingsConfig` C# 类 | `KeyBindingsConfig` Swift 版，默认值一致 | ✅ 可复用上游默认键位 |
| OCR 模型选择 | `OcrFactory` V4Auto/V5Auto/多语言 | 目前仅 V4 中文 | ⚠️ 缺少多语言自动选择 |
| 截图模式选择 | BitBlt / WGC / DXGI 四项 | SCK Window / SCK Display / Mock | ✅ 平台差异，预期行为 |
| 推理设备选择 | TensorRT/CUDA/DML/OpenVINO/CPU | 未暴露（纯 CPU） | ⚠️ 操作系统差异 |

## 九、地图与寻路

| 差异项 | 上游 | macOS 当前 | 影响 |
|--------|------|-----------|------|
| 地图 tile 数据 | NuGet 包 ~200MB PNG tiles | 🔴 未下载/安装 | 地图定位功能完全不可用 |
| 小地图定位 | 模板匹配 tile → 坐标换算 | 🔴 未实现 | 所有 `GetPosition` / `Tp` / `MoveMapTo` 不可用 |
| 寻路 JSON | 49 个 Boss 路线 + tp.json | ✅ `BGIPathExecutor` 可加载和解析 | 解析可用，行走不可用 |
| 导航执行 | WASD + 地图定位 + 动作 | `BGIPathingNavigationBackend` 骨架 | 🔴 真实导航不可用 |
| 传送系统 | 开大地图 → 搜索 → 点击传送点 | 未实现 | 🔴 不可用 |
| 地图遮罩渲染 | WPF 遮罩窗口 | HUD mock 占位 | 🔴 不可用 |

## 十、输入模拟

| 差异项 | 上游 | macOS 当前 | 兼容性 |
|--------|------|-----------|------|
| 键盘 | `SendInput` (Win32) | `CGEvent` post to `cghidEventTap` | ✅ 功能等价 |
| 鼠标移动/点击 | `MOUSEINPUT` absolute/relative | `CGEvent` 绝对坐标 | ✅ 功能等价 |
| 后台输入 | `PostMessage` WM_KEYDOWN 可后台发送 | 不支持（macOS 无窗口消息队列） | ⚠️ 平台差异 |
| 全局热键 | `RegisterHotKey` | SwiftUI 快捷键 + 计划用 CGEvent tap | ⚠️ 实现方式不同 |
| 键鼠录制回放 | `KeyMouseRecorder` / `MacroPlayer` | ✅ 已可解析 JSON 并回放 | ✅ |
| 安全门控 | — | `InputSafetyGate` 三态 + foreground guard | ✅ macOS 独有（更安全） |

## 十一、上游资源直接复用性总表

| 资源类型 | 来源 | 能否直接复制到 macOS 目录使用 | 条件 |
|---------|------|------------------------------|------|
| ONNX 模型 (.onnx) | `BetterGI.Assets.Model` NuGet | ✅ 可直接复制到 `Assets/Model/` | 无 |
| inference.yml 字典 | 模型同级目录 | ✅ 可直接使用 | 需 `BGIModelAssetResolver` 能解析 YAML |
| 模板 PNG | `GameTask/*/Assets/` | ✅ 可直接复制 | 需按 `AssetScale` 缩放 |
| 地图 tile PNG | `BetterGI.Assets.Map` NuGet | ✅ 可直接复制到 `Assets/Map/` | 需实现地图定位引擎 |
| 寻路 JSON | `GameTask/AutoBoss/Assets/Pathing/` | ✅ 可直接复制到 `User/AutoPathing/` | 需实现导航后端 |
| tp.json 传送点 | `GameTask/AutoTrackPath/Assets/` | ✅ 可直接复制 | 需实现传送系统 |
| 脚本仓库 | `bettergi-scripts-list` Git | ✅ 可直接 clone | 部分脚本依赖未实现 API |
| combat_avatar.json | 战斗角色数据库 | ✅ 可直接复制 | 需实现战斗系统 |
| word_list.json | 物品名词典 | ✅ 可直接复制 | 需接入 OCR 过滤 |
| i18n 翻译文件 | `User/I18n/` | ✅ 可直接复制 | 需实现翻译系统 |

## 十二、优先级排序：阻止直接复用上游模型的阻塞项

### 🔴 P0 — 阻塞项（不改则某些模型/脚本无法运行）

1. **YOLO 推理 session 未创建**：5 个 YOLO 模型已注册但无法推理，导致钓鱼/挖矿/世界检测全不可用
2. **Silero VAD 未接入**：AutoSkip 语音等待无法工作
3. **Det 后处理不是旋转矩形**：对倾斜文字检测准确率低，可能导致 Rec 输入质量差
4. **配置无持久化**：重启丢失所有设置，每次需重新配置
5. **地图 tile 未安装 + 地图定位引擎未实现**：所有地图相关 API（Tp, GetPosition）不可用

### 🟡 P1 — 功能缺失（影响部分功能和脚本）

6. **JS 引擎差异**：JavaScriptCore vs V8，部分复杂脚本可能失败
7. **OcrFactory 多语言选择缺失**：非中文用户无法自动选择合适的 OCR 模型
8. **AutoPick 完整触发器缺失**：F 键模板匹配未接入真实决策流
9. **WebView 仓库浏览未实现**：用户无法通过 GUI 浏览/订阅脚本
10. **genshin.* 命令真实后端未接入**：Tp/GetPosition/SwitchParty/AutoFishing 等均为骨架

### 🟢 P2 — 优化项（不影响复用，影响体验）

11. **ONNX Runtime 纯 CPU**：无 GPU 加速，推理延迟较高
12. **模板匹配无 OpenCV**：Rust 自定义实现可能有细微分数差异
13. **音频采集未实现**：VAD 无音频输入源
14. **通知系统未实现**：13 种推送通道全未接入
15. **一键宏/录制回放 UI 未完善**
