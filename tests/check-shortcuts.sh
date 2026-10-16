#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK_DIR="$ROOT/.build/shortcut-check"
mkdir -p "$CHECK_DIR"

python3 - "$ROOT" "$CHECK_DIR/main.swift" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
source, marker, _ = (root / 'QuickChat.swift').read_text().partition('let app = NSApplication.shared\n')
assert marker, 'Uygulama giriş noktası bulunamadı'
Path(sys.argv[2]).write_text(source + (root / 'tests/Shortcuts.swift').read_text())
PY

xcrun swiftc -target "$(uname -m)-apple-macos13.0" -module-cache-path "$CHECK_DIR/module-cache" \
  "$CHECK_DIR/main.swift" -o "$CHECK_DIR/check-shortcuts" \
  -framework Cocoa -framework WebKit -framework Carbon
"$CHECK_DIR/check-shortcuts"
