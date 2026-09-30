# 上游 0.66.1-alpha.1 同步

本轮从 macOS `main` 的 `cbeff258` 双父合并上游 `6a8a9a62`，保留上游提交祖先，版本为 `0.66.1-alpha.1`。

## 共享功能与平台适配

- AutoCombo/Avatar/SkillCd 整体迁移新的角色上下文、E 技能分类、可取消攻击、冷却状态与兜底树；输入继续经过 Mac 平台边界。连招接管冷却展示期间暂停常驻触发器，结束时等待后台循环并释放输入。
- 连招树和兜底树通过 Host RPC 提供给 Swift 设置页；Windows 继续使用 WPF 浮窗。E 分类诊断浮窗保留为 Windows 功能，Mac 战斗逻辑使用同一真实分类模型。
- 至冬秘境 F 选项选择器保留上游 OCR 合并行、滚轮选择与确认算法，接入共享截图、输入、OCR 和自动拾取暂停计数。
- 默认物品识别与自动钓鱼、吃药、合成、分解、奖励识别保持上游 ItemV2 行为；背包计数支持按物品自动分页、排序提前停止，同时保留旧单物品脚本返回值。
- 对话 VAD 同步上下文 64 + 帧 512 的输入和阈值；Windows 诊断界面不进入 portable Core。
- 一条龙 Boss 总次数限制通过真实奖励回调累计并持久化；Swift 提供已完成次数及显式重置。保存旧配置快照不会覆盖运行中更新的计数。
- Mac 音游继续使用共享六轨采样管线，接入最短 80ms 按键保持；路径配置、战斗脚本选择和强制传送同步上游语义。
- WGC、Win11 窗口优化、WPF 本地化和窗口行为保留 Windows 条件边界。

## 资源来源

Model 从 1.0.33 升至官方 NuGet 1.0.36；Map 1.0.24、Other 1.0.27 保持不变。source-lock 根据实际归档重新计算每个模型的路径、长度和 SHA-256，包含新 `e_classify_sim.onnx` 与更新的 `avatar_side_classify_sim.onnx`。模型清单注册 E 分类器，静态 gate 同时约束 AvatarGridIcon、ItemV2 和两项 Common 模型的源版本。

## 验证与发行

执行 Core 完整验证、Fast 契约、运行时路线库闭包检查、Swift 测试和 Windows 解决方案编译，并由 PR 的干净 GitHub runner 再次验证。CI 通过后构建本机稳定 Apple Development 签名 App；合入 main 后推送 GPG 签名版本 tag，触发 macOS Release。

本机开发签名与 GitHub 发布产物的 Developer ID 签名相互独立；云端未配置 Developer ID/公证凭据时，工作流会明确将产物标注为 unsigned。游戏内效果由用户事后测试。
