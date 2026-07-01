#!/usr/bin/env bash
# tests/bash/run.sh — runs every *_test.sh under this dir, aggregates pass/fail.
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

total_files=0
failed_files=0

for t in "$SELF_DIR"/*_test.sh; do
    [[ -e "$t" ]] || continue
    total_files=$((total_files + 1))
    echo "== ${t##*/} =="
    # 2>/dev/null: negative-path tests intentionally emit ERROR/WARN to stderr.
    if bash "$t" 2>/dev/null; then :; else failed_files=$((failed_files + 1)); fi
    echo
done

echo "============================================"
if [[ $failed_files -eq 0 ]]; then
    echo "ALL $total_files test file(s) PASSED"
    exit 0
fi
echo "$failed_files of $total_files test file(s) FAILED"
exit 1
