# BetterGI-mac 源码构建

本仓库同时包含：

- `BetterGenshinImpact/`：上游 Windows WPF 应用及共享业务源码。
- `BetterGenshinImpact.Core/`：macOS Core Host 使用的共享 Core 项目。
- `BetterGenshinImpact.Core.Host/`：随 macOS App 打包的自包含 C# Host。
- `MacGI/`：SwiftUI/AppKit 前端、ScreenCaptureKit 截图与 macOS 输入平台层。

macOS 生产功能必须经过真实 C# Core 和平台 RPC，不应在 Swift UI 中增加业务规则
副本或可见的假实现。

## 获取源码

```bash
git clone https://github.com/Jac0b-Shi/BetterGI-mac.git
cd BetterGI-mac
```

稳定版本位于 `main`。功能开发应从独立分支开始，并在合入前同步本仓库所跟踪的
BetterGI 上游提交。

## 构建 macOS App

### 环境要求

- Apple Silicon Mac。
- macOS 14 或更高版本。
- Xcode/Command Line Tools，以及 Swift 6.1 或兼容版本。
- .NET 8 SDK。
- 用于本地运行的 `Apple Development` 代码签名身份。

先还原并编译 Core：

```bash
dotnet restore BetterGenshinImpact.Core.sln
dotnet build BetterGenshinImpact.Core.sln -c Debug --no-restore
```

运行 Swift 平台层测试：

```bash
swift test --package-path MacGI
```

打包包含自包含 Core Host 的 `.app`：

```bash
MacGI/scripts/package-macgi-app.sh
```

默认输出：

```text
MacGI/.build/App/betterGI-mac.app
```

通过 LaunchServices 启动实际 App Bundle：

```bash
open MacGI/.build/App/betterGI-mac.app
```

不要使用 `swift run` 或直接执行 `.build` 中的 Unix 可执行文件验证屏幕录制权限。
macOS TCC 根据 Bundle ID 和代码签名识别应用；本地开发应保持同一
`Apple Development` 身份。`MACGI_ALLOW_ADHOC_SIGNING=1` 仅用于 CI 打包 smoke，
不适合日常实机运行。

## 构建 Windows 应用

Windows WPF 应用需要 Windows 10/11、Visual Studio 2022 或 Rider，以及
.NET 8 SDK：

```powershell
dotnet build BetterGenshinImpact.sln -c Debug
```

Windows 版的用户下载、使用说明和问题反馈请前往
[BetterGI 上游项目](https://github.com/babalae/better-genshin-impact)。

## 验证工作流

构建依赖后再使用 `--no-build` 运行对应 verifier，避免每次隐式重建完整依赖图。

| 改动范围 | 验证命令 |
| --- | --- |
| Trigger、独立任务设置、调度器编辑 | `scripts/verify-core-fast.sh <suite>` |
| AutoPathing 执行器、handler、路线数据 | `scripts/verify-pathing-library.sh` |
| 架构与生产 fallback | `scripts/verify-core-static.sh` |
| 识别、模型、原生依赖、阶段完成 | `scripts/verify-core-full.sh` |

Swift/AppKit 改动至少运行：

```bash
swift test --package-path MacGI
```

不要为了局部功能改动默认运行无关的完整模型验证，也不要通过 mock 或 fallback
绕过缺失的真实依赖。

## Release 构建

稳定版从 `main` 上的 `v*` SemVer 标签自动构建。配置完整 Developer ID 和公证
凭据时，GitHub Actions 会生成正式签名并公证的 arm64 DMG、ZIP 和 SHA256 清单；
未配置任何凭据时，则生成文件名带 `-unsigned` 的 ad-hoc 临时发布。

仓库管理员配置、标签格式和发布步骤见
[`MacGI/docs/release.md`](../MacGI/docs/release.md)。

## 资源与运行目录

- macOS App 运行目录：`~/Library/Application Support/betterGI-mac/`
- 用户脚本与调度配置：运行目录下的 `User/`
- 随 App 打包的 Core Host：`BetterGI.app/Contents/Resources/BetterGICore/`
- 识别、任务和地图资源：由打包脚本按真实 Core 依赖闭包写入 App Resources

不需要手动从 Windows Release 复制地图或识别资源到编译目录。

修改共享识别资源时，需要同时验证 Windows WPF 编译和 macOS 识别资源闭包。
