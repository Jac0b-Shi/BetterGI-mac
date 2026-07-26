# macOS Release

`macOS Release` publishes a signed and notarized Apple Silicon build when a
semantic version tag is pushed. Release tags must point to a commit contained
in `origin/main`. The workflow runs on GitHub's arm64 `macos-15` image.

## Repository secrets

Configure these Actions secrets before creating a release tag:

| Secret | Value |
| --- | --- |
| `MACGI_CERTIFICATE_P12` | Base64-encoded PKCS#12 containing a Developer ID Application certificate and private key |
| `MACGI_CERTIFICATE_PASSWORD` | Password used when exporting the PKCS#12 |
| `MACGI_NOTARY_APPLE_ID` | Apple ID used by `notarytool` |
| `MACGI_NOTARY_TEAM_ID` | Apple Developer Team ID |
| `MACGI_NOTARY_PASSWORD` | App-specific password for the Apple ID |

The certificate must be a `Developer ID Application` identity. An Apple
Development certificate and ad-hoc signing are intentionally rejected because
they do not provide a stable public release identity.

## Create a release

Merge the release changes into `main`, then create and push a semantic version
tag:

```bash
git switch main
git pull --ff-only origin main
git tag -a v0.1.0 -m "BetterGI macOS v0.1.0"
git push origin v0.1.0
```

Prerelease tags such as `v0.2.0-beta.1` create a GitHub prerelease.
The app bundle uses the corresponding three-part version (`0.2.0`) required by
`CFBundleShortVersionString`, while artifact names and the GitHub release retain
the complete prerelease version.

The workflow publishes:

- `BetterGI-mac-v<version>-arm64.dmg`
- `BetterGI-mac-v<version>-arm64.zip`
- `SHA256SUMS.txt`

Both application containers are notarized, and the DMG includes a shortcut to
`/Applications`.
