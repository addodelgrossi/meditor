# Contributing to Meditor

Thanks for helping make native Mermaid workflows better on macOS.

## Requirements

- macOS 26 or newer
- Xcode 26 with Swift 6.2 or newer
- XcodeGen for regenerating the checked-in Xcode project
- `ffmpeg`, ImageMagick, and `cwebp` when updating documentation media

```bash
brew install xcodegen ffmpeg imagemagick webp
```

## Get started

```bash
git clone https://github.com/addodelgrossi/meditor.git
cd meditor
swift test
./script/build_and_run.sh
```

Local Xcode builds use ad hoc signing, so a development certificate and Apple
Developer account are not required.

## Project map

- `Sources/Meditor/App` defines scenes and application commands.
- `Sources/Meditor/Views` contains the SwiftUI interface.
- `Sources/Meditor/Services` owns rendering, export, syntax, and sharing work.
- `Sources/Meditor/Resources` contains localization and the vendored Mermaid renderer.
- `Sources/MeditorQuickLook` contains the Finder Quick Look extension.
- `Tests` contains core, renderer integration, sharing, and Quick Look tests.
- `docs` is the bilingual GitHub Pages site.
- `AppStore` contains localized store metadata and screenshot sources.

## Common commands

```bash
swift build
swift test
./script/generate_project.sh
./script/build_and_run.sh --verify
./script/verify_quicklook.sh
./script/validate_store_assets.sh
```

Run `./script/generate_project.sh` after changing `project.yml`. Do not edit
generated Xcode project settings when the same change belongs in `project.yml`
or `Configuration/`.

## Localization

The app ships in English and Brazilian Portuguese. User-facing app strings live
in `Sources/Meditor/Resources/Localizable.xcstrings`; Quick Look strings live in
the locale-specific `.lproj` directories.

Keep both languages complete when adding user-facing strings. Pages content and
App Store metadata must also remain aligned in both languages.

## Documentation media

Documentation captures must avoid personal paths and confidential diagrams.
Grant Screen & System Audio Recording permission to the terminal before
capturing real app or Finder media.

```bash
./script/capture_docs_assets.sh
./script/capture_quicklook_demo.sh
```

Review every generated GIF, MP4, poster, and screenshot before committing it.
The documentation media script writes assets to `docs/assets/`.

## Pull requests

- Keep changes focused and follow existing SwiftUI and service boundaries.
- Add tests for behavior changes and regressions.
- Run `swift test` and `./script/validate_store_assets.sh`.
- Explain any privacy, network, entitlement, localization, or distribution impact.

Meditor stores and renders documents locally by default. Changes that add or
alter network behavior must remain explicit to users and be reflected in the
privacy policy and App Store review notes.
