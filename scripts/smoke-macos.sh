#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - <<'PY'
import subprocess
from pathlib import Path
root = Path.cwd()
subprocess.run([str(root / 'build/Focus On.app/Contents/MacOS/FocusOn'), '--smoke-test', str(root / 'artifacts/native-smoke')], check=True, timeout=45)
PY
