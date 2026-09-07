# macOS Release

当前预发布版本说明：[0.64.2-alpha.1](release-0.64.2-alpha.1.md)。

推送 `v*` SemVer 标签后，`macOS Release` 会在 GitHub 的 Apple Silicon
`macos-15` runner 上构建 BetterGI macOS，并将 DMG、ZIP 和 SHA256 清单发布到
GitHub Releases。

Release 标签必须指向已包含在 `origin/main` 中的提交。

## 签名模式

工作流根据仓库 secrets 自动选择两种模式。

### Developer ID

以下五项 secrets 全部存在时，工作流发布正式签名并经过 Apple 公证的安装包：

| Secret | 内容 |
| --- | --- |
| `MACGI_CERTIFICATE_P12` | 包含 Developer ID Application 证书和私钥的 PKCS#12 Base64 |
| `MACGI_CERTIFICATE_PASSWORD` | 导出 PKCS#12 时使用的密码 |
| `MACGI_NOTARY_APPLE_ID` | `notarytool` 使用的 Apple ID |
| `MACGI_NOTARY_TEAM_ID` | Apple Developer Team ID |
| `MACGI_NOTARY_PASSWORD` | Apple ID 的 App 专用密码 |

证书必须包含 `Developer ID Application` 身份。该模式使用 Bundle ID
`cn.jac0bshi.bettergi.mac`，并对 App 和 DMG 执行公证与 staple。

产物名称：

- `BetterGI-mac-v<version>-arm64.dmg`
- `BetterGI-mac-v<version>-arm64.zip`
- `SHA256SUMS.txt`

### Ad-hoc

五项 secrets 全部不存在时，工作流仍会发布明确标记的 ad-hoc 构建：

- Bundle ID：`cn.jac0bshi.bettergi.mac.adhoc`
- 不执行 Apple 公证。
- 产物名包含 `-unsigned`。
- GitHub Release 标题和正文会显示未签名警告。
- GitHub Release 始终标记为 Prerelease，不会成为正式 Latest。

产物名称：

- `BetterGI-mac-v<version>-arm64-unsigned.dmg`
- `BetterGI-mac-v<version>-arm64-unsigned.zip`
- `SHA256SUMS.txt`

ad-hoc 构建不能提供稳定的公开代码身份。Gatekeeper 会要求用户手动允许首次运行，
版本升级后也可能需要重新授予屏幕录制和辅助功能权限。

如果只配置了部分 secrets，工作流会直接失败。这样可以避免本应正式签名的版本在
凭据配置错误时静默降级为 ad-hoc Release。

## 创建 Release

将发布内容合入 `main` 后创建并推送标签：

```bash
git switch main
git pull --ff-only origin main
git tag -a v0.1.0 -m "BetterGI macOS v0.1.0"
git push origin v0.1.0
```

预发布标签示例：

```bash
git tag -a v0.1.0-beta.1 -m "BetterGI macOS v0.1.0-beta.1"
git push origin v0.1.0-beta.1
```

带 prerelease 段的标签会创建 GitHub Prerelease；ad-hoc 模式无论标签名称如何都
会强制创建 Prerelease。App 的 `CFBundleShortVersionString` 使用三段基础版本，
文件名和 GitHub Release 保留完整预发布版本。
