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
ScreenCaptureKit、Wine Bridge、Core Graphics 和 macOS 原生窗口系统完成截图、
输入与 HUD。默认 Wine Bridge 可在原神位于后台时继续投递键鼠输入，同时不移动
用户正在操作的 macOS 光标。

本仓库不是 BetterGI 官方发布，也不由 BetterGI 上游维护者提供支持。Windows
版本请前往[上游项目](https://github.com/babalae/better-genshin-impact)。

## 下载

从本仓库的 [GitHub Releases](https://github.com/Jac0b-Shi/BetterGI-mac/releases)
下载最新的 Apple Silicon 安装文件：

- `BetterGI-mac-v<版本>-arm64.dmg`：推荐的安装镜像。
- `BetterGI-mac-v<版本>-arm64.zip`：应用压缩包。
- 文件名包含 `-unsigned`：ad-hoc 签名、未经 Apple 公证的临时发布。
- `SHA256SUMS.txt`：安装文件校验值。

拥有 Developer ID 后，正式 Release 会使用 Developer ID 签名并经过 Apple 公证。
在此之前，本仓库会明确发布文件名带 `-unsigned` 的 ad-hoc 构建。请勿从第三方
来源下载。ad-hoc 构建始终标记为 GitHub Prerelease，不作为正式 Latest 发布。

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

如果下载文件名包含 `-unsigned`，首次打开时 macOS 会提示无法验证开发者。请在
“系统设置 → 隐私与安全性”中确认该应用来自本仓库 Release 后选择“仍要打开”。
ad-hoc 版本升级后可能需要重新授予屏幕录制和辅助功能权限。

请始终运行已安装到“应用程序”目录的版本，不要直接运行 SwiftPM `.build` 目录
中的可执行文件。

## 使用方法

1. 通过 YAAgl OS 启动原神，进入游戏并保持游戏窗口可见。
2. 打开 BetterGI，在“启动”页面确认两项 macOS 权限均显示“已授权”。
3. 点击“启动”开启 BetterGI Core 和 ScreenCaptureKit 截图器。
4. 如果自动识别不到游戏，展开“手动选择窗口”，选择真实、可见的原神窗口。
5. 默认“输入后端”为 Wine Bridge，适用于 YAAgl/Wine 原神；云原神、远程客户端
   或其他非 Wine 场景请选择“macOS CGEvent”。
6. 截图器进入运行状态后，再按需启用实时任务、独立任务、调度器、脚本或 HUD。
7. 退出游戏后，BetterGI 会自动停止截图器。

## Wine 后台操控

Wine Bridge 是默认和推荐输入后端。它在原神所在的 Wine prefix 内启动原生 Win32
helper，通过 `SendInput` 投递按键、点击、滚轮和相对鼠标移动。切换到浏览器、终端
或 IDE 后，任务仍可继续控制后台原神，真实 macOS 光标不会被 BetterGI 移动，输入
也不会回退并泄漏到当前前台应用。

原神窗口每次从 macOS 前台切到后台后，Wine Bridge 需要先发送一次左键点击来恢复
Wine 输入上下文。实测冷状态下该点击会被 Wine 吞掉，但如果 Wine 提前恢复，它仍
可能表现为一次额外攻击或误点击。应用启动时也会在左下角日志区显示此风险。

“macOS CGEvent”保留为兼容后端，适用于云原神、远程控制另一台电脑或其他不使用
本机 Wine prefix 的客户端。CGEvent 后端仍要求游戏位于 macOS 前台，失焦时会暂停
或拒绝输入，避免操作泄漏到当前应用。

各功能的任务语义和脚本格式以
[BetterGI 文档](https://www.bettergi.com/doc.html)及上游实现为准，但页面位置、
快捷键和部分平台能力可能与 Windows 版不同。

## macOS 权限

| 权限 | 用途 |
| --- | --- |
| 屏幕录制 | 通过 ScreenCaptureKit 读取原神窗口画面，用于识别、定位和任务执行 |
| 辅助功能（无障碍） | 使用 CGEvent 兼容后端、全局快捷键和相关 macOS 输入能力 |

BetterGI 不会在启动截图器时反复请求权限。若本次启动已经发出屏幕录制请求，请在
系统设置中完成授权，然后退出并重新打开应用。

## 已知限制

- 小地图标点继承上游 BetterGI 的定位数据与算法覆盖范围，部分较新的地图区域可能
  不显示标点；大地图标点不受此限制。
- Wine 后台操控当前针对 YAAgl OS 的 Wine 11.0-1 CrossOver 引擎完成验证；其他
  Wine/CrossOver 版本可能需要重新验证输入上下文恢复行为。
- Wine Bridge 在窗口失焦后会发送一次预热点击，少数情况下可能产生一次误输入。
- Wine、YAAgl、游戏版本和 macOS 更新都可能影响截图、窗口识别或模拟输入行为。
- macOS 移植持续跟进上游，但新功能可能不会与 Windows 版同时可用。

## FAQ

### 为什么需要“屏幕录制”和“辅助功能（无障碍）”权限？

macOS 将窗口画面读取和模拟键鼠输入分别置于两个隐私权限下。屏幕录制权限用于
图像识别，辅助功能权限用于实际操作游戏；缺少任意一项时运行时都不会启动。

### 已经授权，为什么仍显示未授权？

屏幕录制权限变更后通常需要重新启动应用。请完全退出 BetterGI，并确认重新打开的
是 `/Applications/BetterGI.app`。开发构建、不同签名或不同 Bundle ID 会被 macOS
视为另一个应用。ad-hoc 版本升级后也可能需要重新授权。

### 为什么找不到原神窗口？

确认游戏窗口真实可见且未退出，然后在“启动”页面使用“手动选择窗口”。登录界面、
启动器窗口或不可见的合成窗口不能作为运行时目标。

### 为什么切到其他应用后任务不再输入？

确认“启动”页面的输入后端为 Wine Bridge，并且游戏通过本机 YAAgl/Wine 运行。
CGEvent 后端、云原神和远程客户端仍受 macOS 前台输入安全策略约束；失焦时暂停是
为了避免 BetterGI 将按键或点击发送到浏览器、终端等当前前台应用。

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

macOS 移植问题请提交到本仓库
[Issues](https://github.com/Jac0b-Shi/BetterGI-mac/issues)，不要提交到 BetterGI
上游。反馈时请附上 macOS 版本、Mac 型号、YAAgl/Wine 版本、游戏分辨率、
BetterGI Release 版本和相关日志。

## 开发

源码构建、验证和发布说明见
[BetterGenshinImpact/README.md](BetterGenshinImpact/README.md)。

## 致谢

- [BetterGI](https://github.com/babalae/better-genshin-impact)：本项目所移植并持续同步的上游原项目。

## 许可证

本项目沿用上游 BetterGI 的 GPL-3.0 许可证。详见 [LICENSE](LICENSE)。
