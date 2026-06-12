# Releasing Meditor

Meditor publishes independent artifacts for GitHub Releases and App Store
Connect. A failure in one release path does not block the other.

## Before tagging

```bash
swift test
./script/validate_store_assets.sh
./script/archive.sh
./script/validate_app_store.sh
```

Increment `CURRENT_PROJECT_VERSION` in `Configuration/Meditor.xcconfig` before
every App Store upload. Set `MARKETING_VERSION` to the semantic version being
released.

To verify the Developer ID and notarization pipeline without publishing:

```bash
gh workflow run github-release.yml -f version=1.1.0
```

## Tagged releases

Push an annotated semantic-version tag:

```bash
git tag -a v1.1.0 -m "Meditor 1.1.0"
git push origin v1.1.0
```

The tag starts two workflows:

- `.github/workflows/github-release.yml` exports a Developer ID signed app,
  creates and notarizes a DMG, validates it with Gatekeeper, and publishes the
  DMG and SHA-256 checksum in a GitHub Release.
- `.github/workflows/app-store.yml` tests, archives, validates, and uploads a
  uniquely numbered build to App Store Connect. It does not submit the version
  for App Review.

The GitHub Release is never published if signing, notarization, stapling, or
Gatekeeper validation fails.

## GitHub environment

Configure an `app-store-connect` GitHub environment with a required reviewer
and these secrets:

- `APP_STORE_CONNECT_API_KEY_ID`
- `APP_STORE_CONNECT_API_ISSUER_ID`
- `APP_STORE_CONNECT_API_KEY_P8`
- `DEVELOPER_ID_CERTIFICATE_P12_BASE64`
- `DEVELOPER_ID_CERTIFICATE_PASSWORD`

Use a least-privilege App Manager API key. Keep API keys and Developer ID
private keys only in GitHub environment secrets.

## Manual distribution commands

```bash
./script/archive.sh
./script/validate_app_store.sh
./script/upload_testflight.sh --confirm-upload
./script/package_github_release.sh
```

Forks can set `APP_STORE_DEVELOPMENT_TEAM` and `DEVELOPER_ID_TEAM` to their own
Apple Developer team IDs.

## Final checks

- Confirm the GitHub Release contains the notarized DMG and checksum.
- Install the DMG and confirm Gatekeeper accepts the app.
- Confirm the uploaded build finishes processing in App Store Connect.
- Attach current localized metadata and screenshots.
- Submit for review and release manually after approval.
