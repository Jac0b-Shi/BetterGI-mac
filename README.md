<div align="center">
  <h1>BetterGI macOS</h1>
  <p>BetterGI 的非官方 macOS 移植</p>
  <p>
    <a href="https://github.com/Jac0b-Shi/BetterGI-mac/releases"><img alt="Release" src="https://img.shields.io/github/v/release/Jac0b-Shi/BetterGI-mac?style=flat-square&logo=github"></a>
    <img alt="平台" src="https://img.shields.io/badge/platform-macOS%2014%2B-black?style=flat-square&logo=apple">
    <img alt="架构" src="https://img.shields.io/badge/architecture-Apple%20Silicon-black?style=flat-square&logo=apple">
    <a href="https://github.com/Jac0b-Shi/BetterGI-mac/actions/workflows/mac-core.yml"><img alt="macOS Core Extraction" src="https://github.com/Jac0b-Shi/BetterGI-mac/actions/workflows/mac-core.yml/badge.svg"></a>
  </p>
</div>

BetterGI macOS 将 [BetterGI](https://github.com/babalae/better-genshin-impact) 的
C# Core、识别资源、任务、脚本与调度能力接入 SwiftUI/AppKit 前端，并使用
ScreenCaptureKit、Core Graphics 和 macOS 原生窗口系统完成截图、输入与 HUD。

本仓库不是 BetterGI 官方发布，也不由 BetterGI 上游维护者提供支持。Windows
版本请前往[上游项目](https://github.com/babalae/better-genshin-impact)。

## 下载

从本仓库的 [GitHub Releases](https://github.com/Jac0b-Shi/BetterGI-mac/releases)
下载最新的 Apple Silicon 安装文件：

- `BetterGI-mac-v<版本>-arm64.dmg`：推荐的安装镜像。
- `BetterGI-mac-v<版本>-arm64.zip`：应用压缩包。
- `SHA256SUMS.txt`：安装文件校验值。

正式 Release 使用 Developer ID 签名并经过 Apple 公证。请勿从第三方来源下载，
也不要将 CI 的 ad-hoc 测试包作为日常安装版本。

## 系统要求

- Apple Silicon Mac。
- macOS 14 或更高版本。
- 能够正常运行原神的 macOS/Wine 环境；当前主要适配和验证
  [YAAgl OS](https://github.com/yaagl/yet-another-anime-game-launcher)。
- 推荐使用 `16:9` 游戏分辨率，并保持游戏亮度为默认值。
- 不建议启用 HDR、画面滤镜或会改变截图颜色的后处理。

Release 已内置自包含的 BetterGI Core，普通用户无需另外安装 .NET。

## 安装

1. 下载并打开 DMG。
2. 将 `BetterGI.app` 拖入 `Applications`。
3. 从“应用程序”目录启动 BetterGI。
4. 首次运行时按“启动”页面提示授予“屏幕录制”和“辅助功能（无障碍）”权限。
5. 完成屏幕录制授权后，完全退出 BetterGI，再从“应用程序”目录重新打开。

为保持 macOS TCC 权限身份稳定，请始终运行已安装的正式应用。不要把
SwiftPM `.build` 目录中的可执行文件或 ad-hoc 签名测试包作为日常版本。

## 使用方法

1. 通过 YAAgl OS 启动原神，进入游戏并保持游戏窗口可见。
2. 打开 BetterGI，在“启动”页面确认两项 macOS 权限均显示“已授权”。
3. 点击“启动”开启 BetterGI Core 和 ScreenCaptureKit 截图器。
4. 如果自动识别不到游戏，展开“手动选择窗口”，选择真实、可见的原神窗口。
5. 截图器进入运行状态后，再按需启用实时任务、独立任务、调度器、脚本或 HUD。
6. 退出游戏后，BetterGI 会自动停止截图器。

当前默认输入后端要求原神是 macOS 前台应用。切换到其他应用时，依赖键鼠输入的
任务会暂停或拒绝发送输入，不会把操作投递给当前前台应用。后台 Wine 输入仍属于
后续实验能力。

各功能的任务语义和脚本格式以
[BetterGI 文档](https://www.bettergi.com/doc.html)及上游实现为准，但页面位置、
快捷键和部分平台能力可能与 Windows 版不同。

## macOS 权限

| 权限 | 用途 |
| --- | --- |
| 屏幕录制 | 通过 ScreenCaptureKit 读取原神窗口画面，用于识别、定位和任务执行 |
| 辅助功能（无障碍） | 通过 Core Graphics 发送经安全门校验的键盘和鼠标输入 |

BetterGI 不会在启动截图器时反复请求权限。若本次启动已经发出屏幕录制请求，请在
系统设置中完成授权，然后退出并重新打开应用。

## 已知限制

- 小地图标点继承上游 BetterGI 的定位数据与算法覆盖范围，部分较新的地图区域可能
  不显示标点；大地图标点不受此限制。
- 当前稳定输入后端不支持在原神失去 macOS 前台焦点后继续操控游戏。
- Wine、YAAgl、游戏版本和 macOS 更新都可能影响截图、窗口识别或模拟输入行为。
- macOS 移植持续跟进上游，但新功能可能不会与 Windows 版同时可用。

## FAQ

### 为什么需要“屏幕录制”和“辅助功能（无障碍）”权限？

macOS 将窗口画面读取和模拟键鼠输入分别置于两个隐私权限下。屏幕录制权限用于
图像识别，辅助功能权限用于实际操作游戏；缺少任意一项时运行时都不会启动。

### 已经授权，为什么仍显示未授权？

屏幕录制权限变更后通常需要重新启动应用。请完全退出 BetterGI，并确认重新打开的
是 `/Applications/BetterGI.app`。开发构建、不同签名或不同 Bundle ID 会被 macOS
视为另一个应用。

### 为什么找不到原神窗口？

确认游戏窗口真实可见且未退出，然后在“启动”页面使用“手动选择窗口”。登录界面、
启动器窗口或不可见的合成窗口不能作为运行时目标。

### 为什么切到其他应用后任务不再输入？

这是当前前台输入安全策略。它用于防止 BetterGI 将按键或点击发送到浏览器、终端等
其他前台应用，不是任务卡死。

### 会不会封号？

任何第三方自动化工具都存在违反游戏用户协议或被检测的风险。本项目不承诺账号
安全，也无法代表游戏运营方给出保证。请自行评估并承担使用风险。

### 在部分地区看不到小地图标点怎么办？

这是上游 Windows 实现同样存在的地图定位覆盖限制，不是 macOS HUD 单独出现的
渲染故障。可改用大地图确认标点，或等待上游补充对应区域支持。

## 免责声明

本项目是社区维护的非官方 BetterGI macOS 移植，与 BetterGI 上游维护者、
米哈游/HoYoverse、YAAgl 及其维护者不存在隶属、授权、背书或合作关系。

本软件按现状提供，不附带任何明示或暗示保证。使用者应自行确认当地法律、游戏用户
协议和账号风险，并对安装、运行、自动化操作以及由此产生的账号、数据或设备损失
承担全部责任。请不要向 BetterGI 上游或游戏官方提交本移植版本特有的问题。

“原神”、相关图像及商标归其各自权利人所有。

## 问题反馈

当前仓库尚未启用 Issues。启用后，macOS 移植问题应只提交到本仓库，不要提交到
BetterGI 上游。反馈时请附上 macOS 版本、Mac 型号、YAAgl/Wine 版本、游戏
分辨率、BetterGI Release 版本和相关日志。

## 开发

源码构建、验证和发布说明见
[BetterGenshinImpact/README.md](BetterGenshinImpact/README.md)。

## 致谢

- [BetterGI](https://github.com/babalae/better-genshin-impact)：本项目所移植并持续同步的上游原项目。

## 许可证

本项目沿用上游 BetterGI 的 GPL-3.0 许可证。详见 [LICENSE](LICENSE)。
