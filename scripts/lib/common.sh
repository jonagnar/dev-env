# scripts/lib/common.sh — shared contract dot-sourced by every verb.
# Mirrors scripts/lib/common.ps1. Callers set DRY_RUN / ASSUME_YES before
# invoking the helpers (defaults below cover tests). This file is meant to be
# *sourced*; it deliberately does NOT enable `set -e` so a failing helper does
# not kill the sourcing test harness — entrypoints set their own strict mode.

# ---- globals (caller-overridable) ----
: "${DRY_RUN:=0}"
: "${ASSUME_YES:=0}"

# ---- logging ----
info()  { printf '%s\n' "$*"; }
warn()  { printf 'WARN: %s\n' "$*" >&2; }
err()   { printf 'ERROR: %s\n' "$*" >&2; }
phase() { printf '\n== %s ==\n' "$*"; }

# ---- run_native: the mockable seam (mirror Invoke-Native) ----
# Runs "$@"; on non-zero exit prints an error and returns that status.
run_native() {
    "$@"
    local rc=$?
    if [[ $rc -ne 0 ]]; then
        err "Command failed (exit $rc): $*"
        return "$rc"
    fi
    return 0
}

# ---- step: dry-run-aware runner (mirror Invoke-Step) ----
# Usage: step "<name>" cmd arg...
# Under DRY_RUN it prints the would-message and returns 0 without running.
step() {
    local name="$1"; shift
    if [[ "$DRY_RUN" == "1" ]]; then
        printf '  [dry-run] would: %s\n' "$name"
        return 0
    fi
    printf '  -> %s\n' "$name"
    "$@"
}

# step_always: like step but runs even under dry-run (read-only steps; -Always).
step_always() {
    local name="$1"; shift
    printf '  -> %s\n' "$name"
    "$@"
}

# ---- confirm (mirror Confirm-Action) ----
# Returns 0 (yes) if ASSUME_YES; under DRY_RUN prints would-prompt and returns 1;
# otherwise reads a line and returns 0 on y/yes.
confirm() {
    local message="$1"
    if [[ "$ASSUME_YES" == "1" ]]; then
        return 0
    fi
    if [[ "$DRY_RUN" == "1" ]]; then
        printf '  [dry-run] would prompt: %s\n' "$message"
        return 1
    fi
    local answer
    read -r -p "$message [y/N] " answer
    [[ "$answer" =~ ^([yY]|[yY][eE][sS])$ ]]
}

# ---- paths ----
dev_root() {
    # common.sh lives at <root>/scripts/lib/common.sh
    cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd
}

age_key_path() {
    printf '%s/.config/sops/age/keys.txt\n' "$HOME"
}

# ---- checklist (mirror Reset/Add/Write-CheckSummary) ----
# Each check: name + ok status (0 = ok/pass, non-zero = fail) + optional detail.
declare -a CHECK_NAMES=()
declare -a CHECK_OK=()
declare -a CHECK_DETAIL=()

reset_checks() { CHECK_NAMES=(); CHECK_OK=(); CHECK_DETAIL=(); }

add_check() { # <name> <ok:0|1> [detail]
    CHECK_NAMES+=("$1")
    CHECK_OK+=("$2")
    CHECK_DETAIL+=("${3:-}")
}

write_check_summary() {
    printf '\nVerification:\n'
    local failed=0 i
    for i in "${!CHECK_NAMES[@]}"; do
        if [[ "${CHECK_OK[$i]}" == "0" ]]; then
            printf '  [ok] %s\n' "${CHECK_NAMES[$i]}"
        else
            printf '  [!!] %s - %s\n' "${CHECK_NAMES[$i]}" "${CHECK_DETAIL[$i]}"
            failed=$((failed + 1))
        fi
    done
    printf '\n'
    if [[ $failed -gt 0 ]]; then
        printf '%d check(s) failed.\n' "$failed"
        return 1
    fi
    printf 'All checks passed.\n'
    return 0
}

# ---- common flag parsing ----
# Sets DRY_RUN / ASSUME_YES from --dry-run / --yes; recognises --help (sets
# SHOW_HELP=1). Leaves unrecognised args in the global REST_ARGS array.
parse_common_flags() {
    REST_ARGS=()
    SHOW_HELP=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run|--what-if) DRY_RUN=1 ;;
            --yes|-y)            ASSUME_YES=1 ;;
            --help|-h)           SHOW_HELP=1 ;;
            *)                   REST_ARGS+=("$1") ;;
        esac
        shift
    done
}
