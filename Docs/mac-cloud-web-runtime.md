# macOS 国服网页云原神预览

入口：主窗口「总览」中，截图器板块下方的「云原神（国服）→ 打开云原神」。游戏页面在独立 WKWebView 窗口中运行，游戏内容保持 16:9，可直接拖动系统标题栏移动窗口，使用官方 `https://ys.mihoyo.com/cloud/?autobegin=1`。登录与排队由用户在官方页面内完成，登录资料保存在独立的持久化 WebKit profile 中。网页弹窗保留原页面及 `window.opener`，不会替换游戏页。

进入游戏、视频持续更新且上游 SDK 的 RTC 通道可用后，点击「用于自动化」，再启动截图器。启动会把游戏窗口置于前台。首版要求保持游戏窗口为键盘焦点；切回主窗口或其他应用会停止自动化并请求释放本会话持有的输入，需要手动重新启动。拖动标题栏时会停止自动化，移动完成后需重新启动截图器，以防使用移动前的坐标。视频区域、窗口大小或显示器像素比例变化也会停止自动化；截图返回前会再次核对区域，丢弃变化期间的旧帧。国际服入口与后台自动化暂不开放。

## 平台边界

- C# Core 继续执行现有触发器、脚本与任务；Swift 提供宿主、截图、输入回调。
- 被动触发器的按键查询合并 SDK 注入集合和游戏窗口处于前台时的系统按键状态；释放仍只处理 SDK 注入集合。
- `CloudWebInputDispatcher` 发送上游 `__ysInputInject` / ClientCore 数据包，不发送模拟 DOM `KeyboardEvent`，不调用 Wine 或全局 CGEvent。
- `Region` 使用实际 video 内容区域。ScreenCaptureKit 捕获窗口后按 WKWebView 的实际位置显式裁剪标题栏与 CSS 留白；窗口的有效像素比例与 SCK 的 1920px 宽度上限一致。云宿主不使用像素比例不一致的 Quartz 回退。
- Web SDK 在 `.page` 内容世界注入，仅供国服官方 HTTPS cloud 页面使用。SDK 未就绪、断流、导航、网页进程退出或输入确认超时均禁用自动化。
- WebKit 会话启动和释放使用一次性回调与 3 秒期限；迟到的回调不能安装旧会话，释放无法确认时关闭网页连接。
- 输入发送时同时核对原生键盘焦点，长按等待期间持续检查网页焦点与可见性；释放不受前台检查限制。长按使用带页面 epoch/deadline 校验的等待，不使用 SDK 内部不可取消的延迟 KeyUp。释放检查 SDK 持有集合，不能确认释放时不返回成功确认。
- 切换 Wine 与云宿主先停止旧 Core；平台回调带本机 generation，旧 Core 的回调不能路由到新宿主。
- SDK 资源与上游 `BetterGenshinImpact/Resources/JavaScript/ys-input-inject.js` 完全一致，静态门禁检查二者一致性。上游依赖网页内部 Webpack module 53638；网站改版可能导致 SDK 不可用，此时界面显示未就绪，不降级为假输入。

## 验证与本机打包

```sh
swift test --package-path MacGI --filter CloudGameContractsTests
node scripts/verify-cloud-web-input.mjs
scripts/verify-core-static.sh
scripts/verify-core-full.sh
MACGI_APP_OUTPUT_ROOT="$PWD/MacGI/.build/CloudWebPreview" \
  MACGI_BUNDLE_VERSION=992 MacGI/scripts/package-macgi-app.sh
```

本地可选设置 `MACGI_SMOKE_DOWNLOAD_CACHE` 为归档目录，加快打包资源验证。归档仍由 ArtifactDownloader 按 source-lock 的 SHA-256 校验；CI 默认从干净目录下载。

编译、合同检查与资源 smoke 不代表真实网页游玩已通过。需用户登录后确认：视频能播放、鼠标视角与键盘响应正常、识别区域无网页留白、停止/失焦后没有残留长按。若网页内部 SDK 或视频兼容性阻止就绪，应根据实际错误继续适配；本预览尚未完成账号内游戏验收。

本轮预览已合入 `main` 的 0.66.2-alpha.4 同步结果，使用 Model 1.0.38，并保留 CPU/OCR 推理设置。
