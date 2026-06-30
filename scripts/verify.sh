#!/usr/bin/env bash
# scripts/verify.sh — read-only health check of the dev-environment.
# Linux port of scripts/verify.ps1.
#   ./scripts/verify.sh            # run checks (exit 0 = all ok, 1 = failure)
#   ./scripts/verify.sh --help
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

# ---- overridable seams (tests stub these) ----
tool_present()  { command -v "$1" >/dev/null 2>&1; }
path_exists()   { [[ -e "$1" ]]; }
# timer_enabled: 0 if the systemd --user backup timer is enabled; non-zero
# otherwise (including when systemd --user is unavailable, e.g. no-systemd WSL).
timer_enabled() {
    systemctl --user is-enabled devenv-backup.timer >/dev/null 2>&1
}
# systemd_user_available: 0 when a systemd --user instance is reachable.
systemd_user_available() {
    systemctl --user is-system-running >/dev/null 2>&1 || \
        [[ -n "${XDG_RUNTIME_DIR:-}" && -S "${XDG_RUNTIME_DIR}/systemd/private" ]]
}

invoke_verify() {
    local root; root="$(dev_root)"
    reset_checks

    local tool
    for tool in git mise sops age chezmoi; do
        if tool_present "$tool"; then add_check "tool: $tool" 0
        else add_check "tool: $tool" 1 "not on PATH"; fi
    done

    local key_path; key_path="$(age_key_path)"
    if path_exists "$key_path"; then add_check "age key present" 0
    else add_check "age key present" 1 "$key_path missing — run init"; fi

    local d
    for d in ops tools/bin backups; do
        if path_exists "$root/$d"; then add_check "folder: $d" 0
        else add_check "folder: $d" 1 "missing"; fi
    done

    # age key round-trip: encrypt a probe to the public key, decrypt with the
    # private key, compare. NEVER trusts run_native's exit alone — compares text.
    local roundtrip=1
    if path_exists "$key_path"; then
        local probe="devenv-roundtrip-probe"
        local tmp enc recipient decrypted
        tmp="$(mktemp 2>/dev/null || echo "/tmp/devenv-probe.$$")"
        enc="$tmp.age"
        printf '%s' "$probe" > "$tmp" 2>/dev/null || true
        recipient="$(run_native age-keygen -y "$key_path" 2>/dev/null)"
        recipient="${recipient//[$'\r\n']/}"
        if [[ -n "$recipient" ]] && run_native age -r "$recipient" -o "$enc" "$tmp" >/dev/null 2>&1; then
            decrypted="$(run_native age -d -i "$key_path" "$enc" 2>/dev/null)"
            decrypted="${decrypted//[$'\r\n']/}"
            [[ "$decrypted" == "$probe" ]] && roundtrip=0
        fi
        rm -f "$tmp" "$enc" 2>/dev/null || true
    fi
    add_check "age key round-trip" "$roundtrip" "encrypt/decrypt failed — key may be wrong"

    # backup timer — soft check: when systemd --user is unavailable, mark ok
    # (skipped) rather than a hard fail.
    if systemd_user_available; then
        if timer_enabled; then add_check "backup timer enabled" 0
        else add_check "backup timer enabled" 1 "devenv-backup.timer not enabled — run init"; fi
    else
        add_check "backup timer enabled (skipped: no systemd --user)" 0
    fi

    write_check_summary
}

main() {
    parse_common_flags "$@"
    if [[ "$SHOW_HELP" == "1" ]]; then
        grep -E '^#( |$)' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
        return 0
    fi
    invoke_verify
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    set -euo pipefail
    main "$@"
fi
