# 0.65 macOS 迁移工作记录

## 冻结基线

- fork 起点：`origin/main@2545d993fba622e4a4928af92f0d22e5b3962bf4`
- 上游本轮目标：`upstream/main@42e1c0e745670eb4443c1e0357fba963eb24dfcd`
- 上游 0.65.0 tag：`f29b0828ab4f8f91d9087152dcb487719e80fa16`
- tag 后额外包含 Assets.Other 1.0.27 更新。
- 分支：`codex/sync-upstream-0.65.0`；保留上游双亲合并历史。

## 平台边界

桌面分身仍为 Windows-only，macOS 使用既有 Wine/Quartz 后台链路。共享业务逐 hunk 合并，保留 Core-owned runtime/RPC、任务取消、输入所有权和释放、截图生命周期。不移植 WGC/HDR 或 XAML 展示实现，不降级已验证的 OpenCvSharp 4.13。

## 当前进度

- 已处理实际 12 个冲突，尚未提交最终合并。
- Core 已显式接入 AutoCombo 源码与 CsTrees 1.0.5、MEAI 1.0.1、AI 10.6.0。
- AutoCombo 配置读取走宿主提供器，秘境保留 IAutoDomainRuntimePlatform。
- 钓鱼保留原有 hardened trigger/input 外壳，退出判定吸收上游主界面识别。
- 奖励汇总与树脂识别已迁移平台输入/截图/OCR；通知截图继续走宿主提供器并统一释放。
- Core 与 Core Host 显式 restore/build 均成功，0 warning / 0 error。
- 奖励汇总开关已接入 Host DTO/保存、Swift RPC/页面和渠道更新保留语义；RuntimeSettings 快验通过，包括旧客户端缺字段保存保留新值。
- AutoCombo 的聊天客户端、队伍识别与运行场景已补显式释放。
- AutoCombo 已接入独立任务的真实建树/运行/暂停请求、四项 Core 配置与 Swift 卡片；API key 使用 SecureField，策略目录支持 combo 而不要求伪策略文件。
- AutoCombo 配置按字段合并保留未知字段，密钥 DTO 标记 secret；服务地址拒绝非 HTTP/HTTPS、非回环 HTTP 和 URL 内嵌凭据。
- `solo-settings` 快验通过，覆盖配置持久化、未知字段保留、secret 契约与 combo 策略目录。
- Swift 应用在 CLT/macOS 26.5 SDK 下真实构建成功；用户完成 Xcode 就绪处理后，完整 Xcode 27 下 `swift test --package-path MacGI` 通过：127 tests / 27 suites。
- Map 1.0.24 / Other 1.0.27 实际下载后锁定整个包的资源内容：725 / 9 个资产，总锁定 769 个文件；记录实际包及成员 SHA-256、大小、NuGet 发布时间和 nuspec 源提交。许可证证据沿用 BetterGI 上游 GPL-3.0 LICENSE，不声称 NuGet 包或 libraries 仓库附有单独许可证。
- 导航 smoke 已从旧 0.62 发布包切换为本轮 source-lock 的 Map 1.0.24。Core 主验证 14,618 passed / 0 failed，包括完整官方包成员对比、真实资源安装、MoonCanon 特征层和模型加载、导航定位及路径执行。
- Release Core solution 显式 restore/build 成功，0 warning / 0 error；静态平台门禁通过。
- 秘境的提升指南选项已接入独立任务与一条龙配置目录；一条龙战斗策略也支持 AutoCombo。新增秘境选项的 solo-settings 快验通过，使用原始 tp.json 资源而非伪造目录。
- `auto-combo` 快验通过：调用真实 OpenAI/MEAI 客户端经回环 HTTP 执行 Sequence/Jump/End/BuildTree 工具并返回会话，确认工具结果回传且不暴露 RunTree；在已发出请求后取消能中断建树。
- Pathing library 验证通过：documents=4978、waypoints=79469、actions=18。
- Xcode 27 / Swift 6.4 的版本和首次启动状态检查成功；Real User 验证通过真实 User 项目的共享 ScriptProject/ClearScript 执行、编译图、生产 Host API 和输入释放。
- Fast 全套通过。AutoCombo 首次全套运行暴露旧套件以最小假资源提前初始化共享角色静态目录的问题；现在在重定向资源根之前用 canonical combat_avatar.json 初始化并验证 AutoCombo，完整全套重跑通过。
- Host 全验首次停在旧的 solo.list 精确目录断言；新增 AutoCombo 后更新预期集合，重建后全验通过（duplex RPC、framing、0600、OpenCV、ClearScript、真实 ScriptProject / zsh、目录保存、调度暂停/恢复和认证）。
- 核对奖励汇总时补齐两处 FindMulti OCR 区域释放，保留原始识别与通知行为；正在重建及最终 Full 复验。
- 树脂识别的两处图标区域也补显式释放。签名 App 首次打包成功，deep/strict、Core dependency 及识别资源 smoke 通过；新增 `--artifacts-smoke` 由打包 Host 按实际 source-lock 安装资源并加载全部 ONNX、解码地图图片，已接入打包流程，待重打包执行。
- 传送两条拖图路径新增 finally 左键释放，避免 Delay/输入/取消异常跳过鼠标抬起，保留上游 60ms 等待；需要在新源码上复跑路径与 Full。当前 Full 首次复验已启动，但不能计为这项后续更改的最终验证。
- 额外交叉核对 Model 1.0.33 与全部 34 个现有模型/侧车成员，发现旧 source-lock 的 Item/items.csv 与新版不同，已切换至 Model 1.0.33 的实际文件及 SHA-256；其余 33 个内容哈希一致。此更改需要新锁文件上的完整安装与最终打包复验，之前旧锁结果不作为最终证明。
- 首次 App 内 artifacts-smoke 实际安装 769 个资源、加载 20 个模型、解码 706 张地图后输出结果，但进程退出时 native mutex 异常导致 134；打包失败，不能计为交付通过。需定位原生退出清理，不使用强制成功退出绕过。
- 对齐正常 Host 的 NativeDependencySmoke 初始化顺序后，资源 smoke 的退出崩溃仍可复现，假设未被证明；正在 LLDB 抓取 `__throw_system_error`。新锁文件和 Tp 释放更改后的 Full 复验正在运行；路径脚本已通过，WPF 复建 0 error / 246 warnings。
- 新锁文件与 Tp finally 更改后的 `scripts/verify-core-full.sh` 已完整通过（Core 14,618 / 0、Host、Real User 和静态门禁）。资源 smoke 已改为通过共享 BgiOnnxFactory / CpuOnnxRuntimePlatform 和模型注册表加载 20 个模型；退出崩溃仍复现。
- LLDB/debugserver 在 task_for_pid 阶段持续等待且无执行进展，已清理本次自建诊断进程。正在使用仅注入自建诊断子进程的临时 dyld throw 跟踪库捕获 native 抛出前堆栈；不会将注入库纳入 App、不会拦截失败当成功。
- 后续仓库读取一度返回 Interrupted system call，未见用户授权弹窗，不能归因于 TCC；恢复后确认诊断子进程已终止。资源检查的提前返回分支遗漏了正常 Host 已有的 OrtEnv 释放；现在该独立命令显式持有环境，待全部 session 释放后、原生静态析构前 Dispose。无注入库、无强制退出的真实命令验证 769 个资源、20 个模型和 706 张地图，退出码 0。正在重新验证签名 App 内流程。
- OrtEnv 清理修复后的 Full 全流程再次通过：Core 14,618 / 0、Host、Real User、静态门禁，脚本退出码 0，日志 /tmp/bgi065-full-after-onnx-cleanup.log。签名 App 内的全新资源根检查仍在下载 Map 1.0.24，未计为通过；本地发布产物尚未封装 ZIP。
- WPF 显式 restore 后交叉构建成功：`dotnet build BetterGenshinImpact/BetterGenshinImpact.csproj -c Debug --no-restore -p:EnableWindowsTargeting=true -m:1 -nr:false`，0 error / 247 warnings（主要为上游过时 API、OpenCV 分析器等，未隐藏警告）。

## 尚待闭环

- AutoCombo 的运行阶段取消与输入释放验证（真实 loopback tool-call 建树和请求取消已通过）。
- 一条龙奖励汇总实际识别与通知路径的验证。
- 新版资源的签名 App 内安装/加载 smoke（Core 主验证已通过，不代替最终打包检查）。
- 新秘境提升指南、战斗/首领/奖励字段与 Swift 配置能力逐项核对；保留 GridIcon 资源与注册直到消费链验证完毕。
- 关键运行生命周期合约快验；完整 Host 全验、WPF 构建及最终 Full 复验（Core 主验 / Real User / Pathing / Static / Swift 已分别通过）。
- 版本说明、签名 App 打包与 smoke；PR 和 CI。
- 用户续跑目标明确要求 CI 全绿后合并、推 GPG 签名 tag 并核验自动 Mac Release；任何失败 gate 未修复前不合并、不推发布 tag。

本轮初始阶段本机 Xcode 尚未就绪，Git 曾使用已有 Command Line Tools 继续；用户随后自行完成就绪处理，完整 Xcode 检查及 Swift 全量测试已通过。未代用户接受法律协议。

历史诊断：CLT 的默认 macOS 27 SDK 缺 SwiftUIMacros 插件，首次 Swift 验证失败于该工具链依赖；macOS 26.5 SDK 与 native SwiftPM 曾完成应用编译，但测试失败于 CLT 缺少 Testing 模块。这些失败未被计为测试成功；后续完整 Xcode 已完成全量验证。
