#!/usr/bin/env bash
# tests/bash/init_test.sh — unit tests for scripts/init.sh
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SELF_DIR/helpers.sh"
source "$SELF_DIR/../../scripts/init.sh"

# stub the heavy seams so we never touch the system
new_dev_age_key()   { return 0; }   # secrets phase
register_backup_task() { return 0; } # schedule phase
invoke_verify()     { return 0; }   # phase 6
ensure_dir()        { return 0; }   # skeleton (don't actually mkdir)
has_cmd()           { return 0; }    # pretend git + mise already present
network_ok()        { return 0; }
install_run_native_mock

# Case 1: dry-run runs zero native commands
DRY_RUN=1; ASSUME_YES=0
reset_native_calls
invoke_init >/dev/null 2>&1
assert_eq "0" "${#NATIVE_CALLS[@]}" "dry-run runs zero run_native calls"

# Case 2: --yes mise-installs the core (git+mise already present via has_cmd)
DRY_RUN=0; ASSUME_YES=1
reset_native_calls
invoke_init >/dev/null 2>&1
assert_true "$(( $(native_calls_matching 'mise install') > 0 ? 0 : 1 ))" "calls mise install"

# Case 3: when mise is absent, init installs it (curl ... | sh seam)
mise_installed=0
has_cmd() { [[ "$1" == "mise" ]] && return 1 || return 0; }   # mise missing, git present
ensure_mise() { mise_installed=1; }   # seam: record that bootstrap was invoked
DRY_RUN=0; ASSUME_YES=1
reset_native_calls
invoke_init >/dev/null 2>&1
assert_eq "1" "$mise_installed" "missing mise -> ensure_mise bootstrap runs"

# Case 4: preflight does NOT abort when not root / git missing under dry-run
unset -f ensure_mise
has_cmd() { return 1; }   # nothing present (git missing)
network_ok() { return 1; }
DRY_RUN=1; ASSUME_YES=0
out="$(invoke_init 2>&1)"; rc=$?
assert_true "$rc" "dry-run preflight never aborts even when git missing"
assert_contains "$out" "WARN" "preflight warns (does not throw) when git missing"

# Case 5: new_dev_age_key renders .sops.yaml from the template with the pubkey.
# Re-source init.sh to restore the REAL new_dev_age_key + ensure_dir (the cases
# above stubbed them to no-ops).
source "$SELF_DIR/../../scripts/init.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
KEY="$WORK/age/keys.txt"
TMPL="$WORK/.sops.yaml.tmpl"
OUT="$WORK/.sops.yaml"
mkdir -p "$WORK/age"
: > "$KEY"   # pre-create so the 'age-keygen -o' branch is skipped
cat > "$TMPL" <<'YAML'
creation_rules:
  - path_regex: \.env\.sops$
    age: "REPLACE_WITH_AGE_PUBLIC_KEY"
YAML
# mock run_native: age-keygen -y returns a fixed fake pubkey; anything else no-op
mock_native_output() {
    if [[ "$1" == "age-keygen" && "$*" == *" -y "* ]]; then printf 'age1faketestkey'; fi
}
install_run_native_mock
new_dev_age_key "$KEY" "$TMPL" "$OUT" >/dev/null 2>&1
rendered="$(cat "$OUT" 2>/dev/null)"
assert_contains "$rendered" "age1faketestkey" "render: .sops.yaml contains the pubkey"
assert_not_contains "$rendered" "REPLACE_WITH_AGE_PUBLIC_KEY" "render: placeholder is gone"
# perm assertions (umask 077 subshell + explicit chmod)
assert_eq "700" "$(stat -c %a "$WORK/age" 2>/dev/null)" "age dir is 700"
assert_eq "600" "$(stat -c %a "$KEY" 2>/dev/null)" "age key is 600"
unset -f mock_native_output

echo "init_test: $((TESTS_RUN - TESTS_FAILED))/$TESTS_RUN passed"
exit "$TESTS_FAILED"
