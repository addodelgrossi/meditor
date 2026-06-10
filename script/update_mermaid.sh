#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-11.15.0}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESTINATION="$ROOT_DIR/Sources/Meditor/Resources/Mermaid"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

cd "$TEMP_DIR"
npm pack "mermaid@$VERSION" --silent >/dev/null
tar -xzf "mermaid-$VERSION.tgz"

mkdir -p "$DESTINATION"
cp package/dist/mermaid.min.js "$DESTINATION/mermaid.min.js"
cp package/LICENSE "$DESTINATION/LICENSE-mermaid.txt"

echo "Vendored Mermaid $VERSION into $DESTINATION"
