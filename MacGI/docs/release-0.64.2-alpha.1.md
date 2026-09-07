# BetterGI macOS 0.64.2-alpha.1

本版本同步冻结的 `upstream/main@b3e46b30`，共享 Core、资源和 Windows WPF 历史均保留。

## 共享吸收

- 同步 AutoFight、AutoFishing（CsTrees 1.0.4）、AutoLeyLineOutcrop、AutoSkip、传送、OCR、日志解析、截图生命周期及地图/模型修复。
- 更新 BetterGI.Assets.Model 1.0.33、BetterGI.Assets.Map 1.0.22，并锁定来源、SHA-256、许可证证据和真实加载检查。
- 接入 QQ 官方机器人与微信 Clawbot 通知、细分地脉花事件、新钓鱼状态机和新增本地化资源。

## macOS 适配

- QQ 私聊/群聊绑定、微信扫码绑定、会话状态和测试发送均由 Core Host RPC 执行，SwiftUI 只提供配置与状态入口。
- 主窗口背景使用原生文件选择器导入到 runtime root，支持启用、清除、填充/适应/拉伸与透明度。
- 界面语言和游戏语言共用 Core 配置目录；任务文本缺失时回退简体中文。
- Wine/Quartz 链路继续负责窗口发现、后台输入、失焦恢复、截图和会话清理。

## Windows-only

- WGC/HDR、注册表和 Windows 窗口检测继续仅由 WPF 项目实现。
- 上游桌面分身（ChildSession/RDP）源码与合并历史保留在 WPF，不进入 Core Host 或 SwiftUI；macOS 使用 Wine 原生后台链路提供对应运行能力。
