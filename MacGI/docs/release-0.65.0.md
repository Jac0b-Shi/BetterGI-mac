# BetterGI macOS 0.65.0

同步冻结的 `upstream/main@42e1c0e745670eb4443c1e0357fba963eb24dfcd`，包含 0.65.0 及其后的 Assets.Other 1.0.27 更新，保留上游双亲合并历史。

## 共享吸收

- 新增实验性 AutoCombo：通过 OpenAI 兼容服务的工具调用构建连招行为树，并供自动战斗、秘境和一条龙任务消费。
- 同步 CsTrees 1.0.5、CsTrees.MEAI 1.0.1 和 Microsoft.Extensions.AI 10.6.0；保持 macOS 已验证的 OpenCvSharp 4.13。
- 同步自动钓鱼退出检测、队伍识别重试、首领路径、传送时序、角色培养、地图模板层与本地化更新。
- 接入一条龙结束奖励汇总：识别原粹/浓缩树脂及每日委托状态，拼接截图并通过现有通知渠道发送。

## macOS 适配

- Swift 提供 AutoCombo 的服务地址、模型、密钥和附加提示配置，以及真实的建树、运行和暂停入口；业务与持久化由 Core 负责，密钥不在 Swift 单独保存。
- 服务地址只允许 HTTPS，回环本地模型可使用 HTTP；拒绝 URL 内嵌凭据。建树请求接受任务取消，识别场景与聊天客户端显式释放。
- 独立任务和一条龙目录提供“根据提升指南选择秘境”与 AutoCombo 策略，不要求创建虚假的战斗策略文件。
- 通知页面提供奖励汇总开关，旧客户端缺少该字段时保存仍保留既有值。
- Map 1.0.24 的 725 个地图资源与 Other 1.0.27 的 9 个资源纳入 SHA-256 source-lock，模型维持 1.0.33；导航验证使用与生产相同的新版地图包。

## Windows-only 与桌面分身替代

WGC V2、GPU/CPU 颜色转换、帧率限制及 XAML 展示保留在 Windows WPF。桌面分身的 ChildSession/RDP 仍不进入 macOS Core、Host 或 SwiftUI；macOS 继续使用 Wine/Quartz 原生后台链路处理窗口、输入、截图与清理。

实现与验证证据见 [迁移工作记录](upstream-0.65-migration.md)；最终签名产物和 PR/CI 结果以交付记录为准。
