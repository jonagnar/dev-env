# tests/bash/helpers.sh — minimal assertion + mock harness for the bash port.
# Sourced by each *_test.sh. Provides assert_* helpers and a mockable run_native
# that records every invocation into NATIVE_CALLS for inspection.

# ---- assertion bookkeeping ----
TESTS_RUN=0
TESTS_FAILED=0

_fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  [FAIL] $*" >&2
}
_pass() { :; }

assert_eq() { # <expected> <actual> <msg>
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$1" == "$2" ]]; then _pass; else _fail "${3:-assert_eq}: expected [$1] got [$2]"; fi
}

assert_true() { # <status:0|1> <msg>   (0 = success/true)
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$1" -eq 0 ]]; then _pass; else _fail "${2:-assert_true}: expected success, got exit $1"; fi
}

assert_false() { # <status> <msg>
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$1" -ne 0 ]]; then _pass; else _fail "${2:-assert_false}: expected non-zero, got 0"; fi
}

assert_contains() { # <haystack> <needle> <msg>
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$1" == *"$2"* ]]; then _pass; else _fail "${3:-assert_contains}: [$1] does not contain [$2]"; fi
}

assert_not_contains() { # <haystack> <needle> <msg>
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$1" != *"$2"* ]]; then _pass; else _fail "${3:-assert_not_contains}: [$1] contains [$2]"; fi
}

# ---- run_native mock ----
# Records each call as a single line "$*" into the NATIVE_CALLS array.
# Tests can set NATIVE_STDOUT to a value to emit on stdout, or define a
# function `mock_native_output` to compute per-call output.
declare -a NATIVE_CALLS=()
NATIVE_STDOUT=""

reset_native_calls() { NATIVE_CALLS=(); }

install_run_native_mock() {
    run_native() {
        NATIVE_CALLS+=("$*")
        if declare -F mock_native_output >/dev/null; then
            mock_native_output "$@"
        elif [[ -n "$NATIVE_STDOUT" ]]; then
            printf '%s' "$NATIVE_STDOUT"
        fi
        return 0
    }
}

# count how many recorded calls match a given substring
native_calls_matching() { # <substring>
    local n=0 c
    for c in "${NATIVE_CALLS[@]:-}"; do
        [[ "$c" == *"$1"* ]] && n=$((n + 1))
    done
    echo "$n"
}
