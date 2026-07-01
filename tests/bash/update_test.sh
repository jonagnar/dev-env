#!/usr/bin/env bash
# tests/bash/update_test.sh — unit tests for scripts/update.sh
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SELF_DIR/helpers.sh"
source "$SELF_DIR/../../scripts/update.sh"

# stub verify so update doesn't actually run health checks
invoke_verify() { return 0; }
install_run_native_mock

# Case 1: dry-run does nothing
DRY_RUN=1; ASSUME_YES=0
reset_native_calls
invoke_update >/dev/null 2>&1
assert_eq "0" "${#NATIVE_CALLS[@]}" "dry-run runs zero run_native calls"

# Case 2: --yes pulls, reconciles mise, applies chezmoi
DRY_RUN=0; ASSUME_YES=1
reset_native_calls
invoke_update >/dev/null 2>&1
assert_true "$(( $(native_calls_matching 'git -C') > 0 && $(native_calls_matching 'pull') > 0 ? 0 : 1 ))" "calls git pull"
assert_true "$(( $(native_calls_matching 'mise install') > 0 ? 0 : 1 ))" "calls mise install"
assert_true "$(( $(native_calls_matching 'mise upgrade') > 0 ? 0 : 1 ))" "calls mise upgrade"
assert_true "$(( $(native_calls_matching 'chezmoi apply') > 0 ? 0 : 1 ))" "calls chezmoi apply"

# Case 3: without --yes (and not dry-run), tool update is skipped (confirm=no)
# confirm() returns 1 when ASSUME_YES=0 and DRY_RUN=0 only after reading stdin;
# feed 'n' to decline.
DRY_RUN=0; ASSUME_YES=0
reset_native_calls
invoke_update </dev/null >/dev/null 2>&1
assert_eq "0" "$(native_calls_matching 'mise')" "declined confirm -> no mise calls"

# Case 4: git pull fails -> update still calls chezmoi apply and returns 0
DRY_RUN=0; ASSUME_YES=1
reset_native_calls
# Override run_native to fail only for "git ... pull"
run_native() {
    local args="$*"
    NATIVE_CALLS+=("$args")
    if [[ "$args" == *"git"* && "$args" == *"pull"* ]]; then
        return 1
    fi
    return 0
}
invoke_update >/dev/null 2>&1
assert_eq "0" "$?" "git pull failure does not abort update (exit 0)"
assert_true "$(( $(native_calls_matching 'chezmoi apply') > 0 ? 0 : 1 ))" "chezmoi apply called despite git pull failure"
# restore the standard mock for any subsequent tests
install_run_native_mock

echo "update_test: $((TESTS_RUN - TESTS_FAILED))/$TESTS_RUN passed"
exit "$TESTS_FAILED"
