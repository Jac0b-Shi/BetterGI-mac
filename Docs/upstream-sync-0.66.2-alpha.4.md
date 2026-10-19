# 0.66.2-alpha.4 上游同步

同步目标为上游 `25e73e50`，稳定基线为 `f29e60f2`（上游 `d533eab0`），共 17 个上游提交。保留直接 merge 的上游祖先关系。

| 变化 | macOS 处理 |
| --- | --- |
| 推理引擎设置与独立运行库 | Windows 接受上游按引擎选择、验证和安装机制。Mac 保留已打包的本机 CPU ONNX Runtime，不加载 Windows DLL；软件设置新增全局线程、OCR CPU 策略及独立 OCR/古树模型验证。 |
| 推理生命周期与并发 | 接受 OCR 会话、工厂及 E 技能识别的同步保护；独立任务每次运行创建预测器并在结束/取消时释放，保留 Mac 注入与 Wine 输入所有权。 |
| JS YOLO | Mac 脚本宿主暴露 `yolo.createPredictor()`，支持检测、分类和配置；模型路径使用现有脚本目录约束，预测器使用本机工厂。 |
| 合成材料加成 | `genshin.craftMaterial(name, count, materialType, bonusType)` 的可选加成参数贯通共享任务及 Mac/Windows runtime。 |
| 自动战斗与传送 | 合入 AutoBoss 大地图/树脂识别修复和传送重试计数调整，保留 Mac 截图与输入抽象。 |
| Model 1.0.38 | 按签名 NuGet 的实际成员更新 source-lock、哈希及来源；新增古树验证图，继续使用规范化模型路径和真实安装/推理检查。 |
| 桌面分身观看模式 | 保留 Windows RDP 实现；Mac 继续使用 Wine/Quartz 后台输入链。 |
| PR 模板与仓库机器人 | 同步上游仓库模板及 Issue 关联配置。 |

Mac 的推理配置保存在 `User/mac-inference.json`。启动时冻结参数；保存仅影响下一次启动，现有 OCR/YOLO 会话不被替换。配置无效时使用本次启动的 CPU 默认值并在设置页显示原因。验证按钮使用独立会话及已保存参数，耗时包含模型加载，不卸载正在使用的识别器。

Windows 的 DirectML/OpenVINO/CUDA 独立安装包不适用于 macOS。Mac 设置只展示实际提供的 CPU 引擎；没有加入未验证的 GPU/CoreML 入口。

云原神在 `codex/mac-hosted-cloud-genshin` 与草稿 PR #20 保留，本轮同步及发布不包含该预览分支。
