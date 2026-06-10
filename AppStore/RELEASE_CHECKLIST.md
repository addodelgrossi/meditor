# Meditor 1.0 Mac App Store release checklist

## Ready in the repository

- [x] Xcode app and test targets with automatic signing for team `QHURUB34Z9`
- [x] Bundle ID `com.addodelgrossi.meditor`, version `1.0.0`, build `1`
- [x] App Sandbox, user-selected file access, privacy manifest, and export compliance
- [x] Complete app icon, English and Brazilian Portuguese localizations
- [x] About & Legal UI, MIT license, and Mermaid dependency notice
- [x] App Store metadata, review notes, screenshot sources, privacy, and support pages
- [x] Swift Package and Xcode test suites
- [x] Universal Release archive validated locally

## Apple account and App Store Connect

- [ ] Confirm the explicit Bundle ID exists in Certificates, Identifiers & Profiles
- [ ] Accept pending agreements and complete the applicable trader declaration
- [ ] Create a new macOS app:
  - Name: `Meditor: Mermaid Editor`
  - Fallback name: `Meditor for Mermaid`
  - Primary language: English (U.S.)
  - Bundle ID: `com.addodelgrossi.meditor`
  - SKU: `meditor-macos-001`
- [ ] Fill in the private App Review contact email and phone
- [ ] Set price to Free, manual release, worldwide availability
- [ ] Set categories to Developer Tools and Productivity
- [ ] Complete age rating, content rights, and export compliance questionnaires
- [ ] Declare App Privacy as Data Not Collected

The App Store validation script currently stops because the App Store Connect
record for `com.addodelgrossi.meditor` does not exist yet. Once created, run:

```bash
./script/validate_app_store.sh
```

## GitHub Pages and screenshots

- [ ] Push the repository and enable GitHub Pages with GitHub Actions
- [ ] Verify these public URLs:
  - <https://addodelgrossi.github.io/meditor/privacy/>
  - <https://addodelgrossi.github.io/meditor/support/>
- [ ] Grant Screen & System Audio Recording access to Codex or Terminal
- [ ] Generate and visually approve both screenshot sets:

```bash
./script/capture_screenshots.sh en-US
./script/capture_screenshots.sh pt-BR
```

## TestFlight and review

- [ ] Increment `CURRENT_PROJECT_VERSION` before every new upload
- [ ] Create and validate the final archive:

```bash
./script/archive.sh
./script/validate_app_store.sh
```

- [ ] Upload only after the App Store Connect record is complete:

```bash
./script/upload_testflight.sh --confirm-upload
```

- [ ] Test the build with internal TestFlight
- [ ] Attach screenshots, localized metadata, and the prepared review notes
- [ ] Submit for App Review and release manually after approval
