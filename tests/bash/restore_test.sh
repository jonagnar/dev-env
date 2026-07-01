#!/usr/bin/env bash
# tests/bash/restore_test.sh — unit tests for scripts/restore.sh
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SELF_DIR/helpers.sh"
source "$SELF_DIR/../../scripts/restore.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

get_latest_archive() { printf '%s\n' "$WORK/backups/dev-backup-x.tar.age"; }
install_run_native_mock

# Case 1: dry-run does nothing (and confirm returns false under dry-run -> abort)
DRY_RUN=1; ASSUME_YES=0
reset_native_calls
invoke_restore --backup-dir "$WORK/backups" >/dev/null 2>&1
assert_eq "0" "${#NATIVE_CALLS[@]}" "dry-run runs zero run_native calls"

# Case 2: --yes decrypts then extracts to a staging dir
DRY_RUN=0; ASSUME_YES=1
reset_native_calls
invoke_restore --backup-dir "$WORK/backups" >/dev/null 2>&1
assert_true "$(( $(native_calls_matching 'age -d') > 0 ? 0 : 1 ))" "calls age -d (decrypt)"
assert_true "$(( $(native_calls_matching 'tar -xf') > 0 ? 0 : 1 ))" "calls tar -xf (extract)"

# get_latest_archive: picks newest by mtime (not name)
unset -f get_latest_archive
source "$SELF_DIR/../../scripts/restore.sh"
mkdir -p "$WORK/bk"
touch -d "2024-01-01 00:00:00" "$WORK/bk/dev-backup-20250601-120000.tar.age"
touch -d "2025-06-01 12:00:00" "$WORK/bk/dev-backup-20240101-000000.tar.age"
latest="$(get_latest_archive "$WORK/bk")"
assert_contains "$latest" "20240101-000000" "latest archive is the newest by mtime (not name)"

echo "restore_test: $((TESTS_RUN - TESTS_FAILED))/$TESTS_RUN passed"
exit "$TESTS_FAILED"
