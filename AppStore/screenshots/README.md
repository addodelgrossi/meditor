# Mac App Store screenshots

Generate screenshots at **2880 × 1800** for both `en-US` and `pt-BR`.
Use the same visual sequence for each localization:

1. Welcome screen and built-in template gallery
2. Flowchart source with live split preview
3. Sequence diagram with syntax highlighting
4. Larger architecture diagram in split mode
5. Full preview of the architecture diagram

Run `./script/capture_screenshots.sh en-US` and
`./script/capture_screenshots.sh pt-BR` after building the Release app. Review
every image before uploading; the script prepares clean captures but final
marketing composition remains a visual approval step.

The capture command requires Screen & System Audio Recording permission for
Codex or Terminal in macOS System Settings > Privacy & Security.
