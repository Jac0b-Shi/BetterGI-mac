# 如何创建 Release Tag

本文面向需要发布 macOS 版本的维护者，说明如何通过推送 tag 触发自动编译与发布。

## 发布流程概览

推送一个符合规范的 tag 到远端后，`.github/workflows/mac-release.yml` 会自动执行：

1. **`verify-tag`（Ubuntu，秒级）**：校验 tag 的命名、类型、签名和指向。校验失败会直接终止，不会消耗 macOS 编译资源。
2. **`release`（macOS）**：编译、签名、打包 DMG/ZIP，并发布 GitHub Release。

可以在仓库的 **Actions** 页面查看进度；Release 标题为 `BetterGI macOS <版本号>`。

## 前置条件（首次发布前配置一次）

发布需要一把已上传到 GitHub 账号的 GPG 密钥：

```bash
# 1. 如果没有密钥，先生成（推荐 ed25519）
gpg --quick-generate-key "你的名字 <邮箱>" ed25519 sign never

# 2. 查看密钥指纹（40 位）
gpg --list-secret-keys --keyid-format long

# 3. 告诉 git 用哪把密钥签名
git config --global user.signingkey <密钥ID或指纹>

# 4. 导出公钥，上传到 GitHub → Settings → SSH and GPG keys
gpg --armor --export <密钥ID或指纹>
```

> 公钥上传后，会出现在 `https://github.com/<你的用户名>.gpg`，CI 正是从这里拉取公钥验证 tag 签名。

## Tag 规范

1. **命名**：`v` 前缀 + 语义化版本号，例如 `v0.63.0`、`v0.63.0-beta.1`。
   - 版本号以 `BetterGenshinImpact/BetterGenshinImpact.csproj` 中的 `<Version>` 为准，由上游维护迭代，发布前请确认与之一致。
2. **类型**：必须是 **GPG 签名的附注 tag（signed annotated tag）**。轻量 tag（lightweight tag）和未签名的附注 tag 都会被拒绝。
3. **签名密钥**：签名密钥的指纹必须在 `mac-release.yml` 的 `RELEASE_SIGNING_FINGERPRINT` 白名单中（当前为仓库所有者的密钥）。新增维护者时，需要将其指纹加入白名单，并确保其公钥已上传到 GitHub。
4. **指向**：tag 必须指向 `main` 分支上的提交（通常是合并 PR 后的 HEAD），workflow 会校验该提交是否在 `main` 历史中。

## 发布步骤

```bash
# 1. 同步 main
git checkout main
git pull

# 2. 确认版本号
grep "<Version>" BetterGenshinImpact/BetterGenshinImpact.csproj

# 3. 创建 GPG 签名附注 tag（不要使用 --no-sign）
git tag -s v0.63.0 main -m "Release v0.63.0"

# 4. 本地自检（可选但推荐）
git tag -v v0.63.0   # 应显示 "Good signature"

# 5. 推送 tag，触发 release 编译
git push origin v0.63.0
```

推送后约 5 分钟左右出 Release；如果是 beta/alpha 等预发布版本号，会自动标记为 Pre-release。

## 常见错误

CI 的 `verify-tag` 任务失败时，错误消息与原因对照：

| 错误消息 | 原因与解决 |
| --- | --- |
| `lightweight tags are not accepted` | 用了 `git tag v0.63.0`（轻量 tag），改用 `git tag -s` |
| `signature verification failed` | tag 未签名，或签名公钥未上传到 GitHub 账号 |
| `signed by an unauthorized key` | 签名密钥指纹不在 `RELEASE_SIGNING_FINGERPRINT` 白名单中 |
| `does not contain the pinned release signing key` | CI 从 GitHub 拉到的公钥集中没有白名单指纹，检查公钥是否上传到了正确的账号 |
| `Tag must use semantic versioning` | tag 名缺少 `v` 前缀或不是合法语义化版本号 |

## 删除错误的 tag

```bash
git push origin :refs/tags/v0.63.0   # 删远端
git tag -d v0.63.0                   # 删本地
```

注意：删除 tag **不会**自动取消已触发的 workflow 运行，需要到 Actions 页面手动取消，否则可能产生重复的 Release。已发布的 Release 需要单独在 Releases 页面删除。
