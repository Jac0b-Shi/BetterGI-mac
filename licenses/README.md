# ImageSharp 社区许可证

`BetterGenshinImpact.Core` 直接引用 ImageSharp 4.1.3。其正式构建需要有效的 Six Labors 许可证，项目通过 `SixLaborsLicenseFile` 加载 `sixlabors-BetterGenshinImpact.Core.lic`。

仓库内许可证覆盖 `BetterGenshinImpact.Core`，有效期至 2028-01-10；正式构建仍以官方校验结果为准。

本目录只允许提交官方明确允许公开的、以 `Key=Assembly:` 标记并覆盖 `BetterGenshinImpact.Core` 的程序集范围社区许可证。不提交商业许可证或未限定程序集的密钥，不跳过许可证验证。构建者也可以通过 MSBuild 的 `SixLaborsLicenseFile` 属性指定自己的许可证文件。

许可证过期前 90 天，可以使用原申请邮箱和相同程序集名称申请续期。修改 `AssemblyName` 后须申请覆盖新名称的许可证。

- [官方构建与公开仓库规则](https://docs.sixlabors.com/articles/imagesharp/index.html#community-keys-for-public-projects)
- [免费社区许可证申请及续期](https://licensing.sixlabors.com/)
