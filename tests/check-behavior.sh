#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK_DIR="$ROOT/.build/behavior-check"
mkdir -p "$CHECK_DIR"
python3 - "$ROOT" "$CHECK_DIR/main.swift" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
source, marker, _ = (root / 'QuickChat.swift').read_text().partition('let app = NSApplication.shared\n')
assert marker
Path(sys.argv[2]).write_text(source + (root / 'tests/Behavior.swift').read_text())
PY
xcrun swiftc -target "$(uname -m)-apple-macos13.0" -module-cache-path "$CHECK_DIR/module-cache" \
  "$CHECK_DIR/main.swift" -o "$CHECK_DIR/check-behavior" \
  -framework Cocoa -framework WebKit -framework Carbon
"$CHECK_DIR/check-behavior"
