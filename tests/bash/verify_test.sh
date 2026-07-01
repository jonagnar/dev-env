#!/usr/bin/env bash
# tests/bash/verify_test.sh — unit tests for scripts/verify.sh
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SELF_DIR/helpers.sh"
source "$SELF_DIR/../../scripts/verify.sh"

# Verify uses helper seams we can override: tool_present, path_exists,
# timer_enabled, and run_native (for age/age-keygen). The round-trip probe is
# the constant 'devenv-roundtrip-probe'.

# Case 1: age key missing -> exit 1
tool_present() { return 0; }            # all tools present
path_exists()  { [[ "$1" != *keys.txt* ]]; }  # everything exists EXCEPT keys.txt
timer_enabled() { return 0; }
install_run_native_mock
invoke_verify >/dev/null 2>&1
assert_false $? "missing age key -> exit 1"

# Case 2: all pass, round-trip decrypts to the probe -> exit 0
tool_present() { return 0; }
path_exists()  { return 0; }
timer_enabled() { return 0; }
mock_native_output() {
    # age-keygen -y -> recipient ; age -d ... -> the probe
    if [[ "$1" == "age-keygen" ]]; then printf 'age1fakeRecipient'
    elif [[ "$1" == "age" && "$*" == *" -d "* ]]; then printf 'devenv-roundtrip-probe'
    fi
}
invoke_verify >/dev/null 2>&1
assert_true $? "all checks pass + correct round-trip -> exit 0"

# Case 3: round-trip returns wrong plaintext -> exit 1
mock_native_output() {
    if [[ "$1" == "age-keygen" ]]; then printf 'age1fakeRecipient'
    elif [[ "$1" == "age" && "$*" == *" -d "* ]]; then printf 'WRONG'
    fi
}
invoke_verify >/dev/null 2>&1
assert_false $? "wrong round-trip plaintext -> exit 1"

unset -f mock_native_output

echo "verify_test: $((TESTS_RUN - TESTS_FAILED))/$TESTS_RUN passed"
exit "$TESTS_FAILED"
