#!/usr/bin/env bash
# tests/bash/common_test.sh — mirrors tests/common.Tests.ps1
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/bash/helpers.sh
source "$SELF_DIR/helpers.sh"
# shellcheck source=scripts/lib/common.sh
source "$SELF_DIR/../../scripts/lib/common.sh"

# run_native: throws (non-zero) on failure, zero on success
run_native true;  assert_true  $? "run_native zero exit succeeds"
run_native false; assert_false $? "run_native non-zero exit fails"

# step: skips action under dry-run
DRY_RUN=1; ASSUME_YES=0
ran=0
out="$(step "do thing" bash -c 'echo RAN' 2>&1)"; ran=$?
assert_contains "$out" "[dry-run] would: do thing" "step dry-run prints would-message"
assert_not_contains "$out" "RAN" "step dry-run does not run the action"

# step: runs action when not dry-run
DRY_RUN=0
out="$(step "do thing" bash -c 'echo RAN')"
assert_contains "$out" "RAN" "step runs action when not dry-run"

# step_always: runs even under dry-run
DRY_RUN=1
out="$(step_always "read-only" bash -c 'echo RO')"
assert_contains "$out" "RO" "step_always runs under dry-run"
DRY_RUN=0

# confirm: true without prompting when ASSUME_YES
ASSUME_YES=1; DRY_RUN=0
confirm "overwrite?"; assert_true $? "confirm true when ASSUME_YES"

# confirm: false under dry-run without prompting
ASSUME_YES=0; DRY_RUN=1
out="$(confirm "overwrite?" 2>&1)"; rc=$?
assert_false "$rc" "confirm false under dry-run"
assert_contains "$out" "would prompt" "confirm prints would-prompt under dry-run"
DRY_RUN=0

# checklist: failure -> summary returns 1
reset_checks
add_check "key present" 0
add_check "tools installed" 1 "mise missing"
write_check_summary >/dev/null; assert_false $? "summary returns 1 when a check fails"

# checklist: all pass -> returns 0
reset_checks
add_check "key present" 0
write_check_summary >/dev/null; assert_true $? "summary returns 0 when all pass"

# dev_root resolves to parent of scripts/
expected="$(cd "$SELF_DIR/../.." && pwd)"
assert_eq "$expected" "$(dev_root)" "dev_root resolves repo root"

# age_key_path under HOME
assert_contains "$(age_key_path)" "$HOME" "age_key_path under HOME"
assert_contains "$(age_key_path)" "keys.txt" "age_key_path ends in keys.txt"

# report
echo "common_test: $((TESTS_RUN - TESTS_FAILED))/$TESTS_RUN passed"
exit "$TESTS_FAILED"
