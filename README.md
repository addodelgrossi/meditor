# Meditor

A focused, native Mermaid editor for macOS 26.

## Highlights

- Native `.mmd` and `.mermaid` documents with autosave, undo, versions, and multiple windows
- TextKit editor with syntax highlighting, line numbers, completion, and inline error location
- Fully offline Mermaid 11.15.0 preview with pan, zoom, themes, and last-valid-preview recovery
- SVG, PNG, and PDF export plus clipboard support
- English and Brazilian Portuguese interface

## Build and run

```bash
./script/build_and_run.sh
```

Run tests with:

```bash
swift test
```

Update the vendored Mermaid renderer with:

```bash
./script/update_mermaid.sh 11.15.0
```
