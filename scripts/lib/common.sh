# scripts/lib/common.sh — shared contract for the bash entrypoints.
# SCAFFOLD: mirrors lib/common.ps1; functions are stubs this cycle.
set -euo pipefail
dev_root() { cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd; }
not_implemented() { echo "not yet implemented on this platform (bash scaffold) — use the PowerShell verb on Windows." >&2; exit 2; }
