# 上游 0.66.2-alpha.2 同步

本轮从 macOS main 的 `ca1f10ed` 直接合并上游 `d533eab0`，保留全部 30 个上游提交的祖先关系。版本为 `0.66.2-alpha.2`，同时包含该版本提交之后的功能与修复。

## 平台适配

- InputHub 在 Mac 上通过 MacTaskControlInputBackend 接入现有 TaskControlPlatform，Foreground/Background 共用既有 Wine/Quartz 会话输入 owner。任务运行时拒绝切换 InputHub 后端；切换本身不发送全局 key-up。通道发送按下事件与记账、ReleaseAll 串行，释放仅针对自己记录的输入，失败保留记录供重试。
- MacTriggerDispatcher 每帧比较配置、任务请求及实际启用状态，串行调用 OnEnabled/OnDisabled。设置更新走重启边沿；关闭、失焦及移除实例先结束钓鱼会话再清理对象，保留 session CTS 与不可重入 tick。Wine 支持后台投递时不依赖宿主前台焦点；Quartz 仍使用现有焦点恢复机制。
- IMaskWindowDrawingBoard 映射到 MacOverlayDrawingBoard，经 Host 发布完整、不可变快照，Swift Canvas 绘制矩形、线段及带样式文字。合并的是变更通知，删除不会被中间帧丢弃；Feature 与 Recognition 保持各自显示开关语义。区域树继承绘制入口及截图物理像素坐标。
- 高分辨率截图通过共享 DeriveTo1080P 和 ScaleConverter 保持比例；输入与 HUD 坐标沿截图区域树转换回实际捕获像素。
- Windows GameRuntime、WebView2、WPF 遮罩及配置防抖/原子写完整保留在 Windows 边界。Mac 保留 Host JSON 配置存储与现有 Wine/Quartz 宿主。MacWineRuntime、MacForegroundRuntime、MacHostedWebRuntime 类型已预留；本次不提供 Mac 网页云原神宿主。
- Desktop Clone/ChildSession/RDP 继续为 Windows 专属，Mac 使用原生 Wine 后台链。

## 共享功能

- 自动演奏同步重复音重触发与稳定事件排序，保留 Mac 停止、冻结及恢复时的输入清理。
- 自动连招支持 OpenAI/Anthropic 服务商、模型列表查询及分页；Host RPC 与 Swift 设置页提供服务商及模型选择，密钥仍为 secret。无 provider 的旧配置默认 OpenAI；模型列表拒绝跨源重定向。
- Discord Bot 支持频道/私信、多目标及 Plain/Embed 格式；Mac 设置页以集合保存目标，兼容既有 Webhook。QQ Bot 设置同步文本/Markdown 格式选择。
- 自动秘境在指定队伍切换后启动建树；退出时取消并等待后台建树任务，避免任务结束后继续更新预览。任务触发器租约支持嵌套所有者恢复。
- 同步任务进度续跑、幽境危战追踪点重试、元素采集角色、武器名称 OCR、夜兰长按技能冷却与自动邀约文本修复。

## 资源与验证

Model 1.0.36、Map 1.0.24、Other 1.0.27、CsTrees.MEAI 1.0.2 保持原版本和锁定哈希。更新 artifactSetVersion 标识本轮 App；七圣召唤 7.1 卡牌、邀约和战斗角色 JSON 进入 canonical GameTask staging。

执行 Fast、Core/Host/真实用户脚本、Pathing、静态架构、Swift 测试及 Windows 编译，再由 PR CI 验证干净 runner。最小新增契约覆盖输入释放竞态、触发器生命周期、遮罩快照、重复音排序与模型查询跨源密钥保护。

Core 的 ImageSharp 从 3.1.12 升至 4.1.2，以修复当前 NuGet audit 报告的漏洞；未关闭漏洞检查。新版本会提示 Six Labors 许可证配置，发行使用应遵循该依赖的授权条款。

CI 通过并合入 main 后，构建本机稳定 Apple Development 签名 App，验证 App/Helper 签名及实际资源加载；随后推送 GPG 签名 tag，验证 macOS Release 产物及 SHA-256。本机开发签名与云端 Developer ID/公证签名分开报告。游戏内效果由用户事后测试。
