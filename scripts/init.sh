#!/usr/bin/env bash
# scripts/init.sh — provision or refresh this machine for the dev-environment.
# Linux port of scripts/init.ps1.
#   ./scripts/init.sh --dry-run    # preview
#   ./scripts/init.sh --yes        # provision non-interactively
#
# Linux substitutions vs init.ps1:
#   * No root required. Preflight only warns (git missing / no network); under
#     --dry-run warnings never abort.
#   * scoop install git mise  -> ensure mise via `curl https://mise.run | sh`
#     (user-scope ~/.local/bin); git is only warned about (no auto-sudo).
#   * Register-ScheduledTask   -> systemd --user timer (graceful skip if absent).
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/verify.sh"   # provides invoke_verify

# ---- overridable seams (tests stub these) ----
has_cmd()    { command -v "$1" >/dev/null 2>&1; }
network_ok() {
    # cheap reachability probe; tolerant of missing tools.
    if has_cmd curl; then curl -fsS --max-time 5 -o /dev/null https://mise.run 2>/dev/null
    elif has_cmd ping; then ping -c1 -W2 1.1.1.1 >/dev/null 2>&1
    else return 1; fi
}
ensure_dir() { mkdir -p "$1"; }

# Bootstrap mise user-scope (curl https://mise.run | sh -> ~/.local/bin).
ensure_mise() {
    run_native bash -c 'curl -fsSL https://mise.run | sh' || return 1
    export PATH="$HOME/.local/bin:$PATH"
}

# Generate the work age key + render .sops.yaml from the template with the pubkey.
new_dev_age_key() {
    local key_path="$1" sops_tmpl="$2" sops_config="$3"
    local dir; dir="$(dirname "$key_path")"
    # umask 077 in a subshell so every dir/file created here is private from
    # birth (don't rely on age-keygen's default mode or the inherited umask).
    # NOTE: no `local` inside the subshell — `local` is only valid in a function
    # body, and a ( ) subshell is not one; `pub` is a plain var here.
    (
        umask 077
        ensure_dir "$dir"
        chmod 700 "$dir" 2>/dev/null || warn "could not chmod 700 $dir"
        if [[ ! -f "$key_path" ]]; then
            run_native age-keygen -o "$key_path" || exit 1
        fi
        chmod 600 "$key_path" 2>/dev/null || warn "could not chmod 600 $key_path"
        pub="$(run_native age-keygen -y "$key_path")" || exit 1
        pub="${pub//[$'\r\n']/}"
        ensure_dir "$(dirname "$sops_config")"
        sed "s|REPLACE_WITH_AGE_PUBLIC_KEY|$pub|" "$sops_tmpl" > "$sops_config"
    ) || return 1
}

# Register a systemd --user daily backup timer (Persistent for catch-up).
# Gracefully skips (warn) when systemd --user is unavailable (e.g. WSL w/o systemd).
register_backup_task() {
    local root="$1"
    if ! systemctl --user is-system-running >/dev/null 2>&1; then
        warn "systemd --user not available — skipping backup timer registration."
        return 0
    fi
    local unit_dir="$HOME/.config/systemd/user"
    ensure_dir "$unit_dir"
    cat > "$unit_dir/devenv-backup.service" <<EOF
[Unit]
Description=dev-environment encrypted backup

[Service]
Type=oneshot
ExecStart="${root}/scripts/backup.sh" --yes
EOF
    cat > "$unit_dir/devenv-backup.timer" <<'EOF'
[Unit]
Description=Daily dev-environment backup (catch-up enabled)

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOF
    run_native systemctl --user daemon-reload || return 1
    run_native systemctl --user enable --now devenv-backup.timer || return 1
}

invoke_init() {
    parse_common_flags "$@"
    local root; root="$(dev_root)"

    phase "Phase 0 — Preflight"
    # No root required on Linux. Warn-only checks; never abort under dry-run.
    if ! has_cmd git; then
        warn "git not found — install it (e.g. 'sudo apt install git'). Continuing."
    fi
    if ! network_ok; then
        warn "Network probe failed — tool downloads may not work."
    fi

    phase "Phase 1 — Tools"
    if ! has_cmd mise; then
        step "install mise (curl https://mise.run | sh)" ensure_mise || return 1
    else
        info "mise already present."
    fi
    step "mise install core (sops age chezmoi gitleaks)" _init_mise_install "$root" || return 1
    # Put the just-installed mise tools on PATH for the rest of THIS process —
    # chezmoi (Phase 3), age-keygen (Phase 4) and verify (Phase 6) run here,
    # before any new shell activates mise.
    if [[ "${DRY_RUN:-0}" -ne 1 ]] && command -v mise >/dev/null 2>&1; then
        eval "$(MISE_GLOBAL_CONFIG_FILE="$root/.config/mise/core.toml" mise env -s bash 2>/dev/null)" || true
    fi

    phase "Phase 2 — Skeleton"
    local d
    for d in ops tools/bin backups; do
        step "ensure $d/" ensure_dir "$root/$d" || return 1
    done

    phase "Phase 3 — Host config"
    step "chezmoi init --apply" _init_chezmoi "$root" || return 1

    phase "Phase 4 — Secrets"
    step "generate work age key + write recipient" \
        new_dev_age_key "$(age_key_path)" \
        "$root/.config/sops/.sops.yaml.tmpl" \
        "$root/.config/sops/.sops.yaml" || return 1
    info "Store the PRIVATE key (~/.config/sops/age/keys.txt) in your password manager (Bitwarden/Vaultwarden) + offline."

    phase "Phase 5 — Schedule"
    step "register daily catch-up backup timer" register_backup_task "$root" || return 1

    phase "Phase 6 — Verify"
    if [[ "$DRY_RUN" != "1" ]]; then
        invoke_verify >/dev/null || true
    fi
}

_init_mise_install() {
    local root="$1"
    local cfg="$root/.config/mise/core.toml"
    MISE_GLOBAL_CONFIG_FILE="$cfg" run_native mise trust "$cfg"
    MISE_GLOBAL_CONFIG_FILE="$cfg" run_native mise install
}

_init_chezmoi() {
    local root="$1"
    DEV_ROOT="$root" run_native chezmoi init --apply --source "$root/.config/chezmoi"
}

main() {
    if [[ " $* " == *" --help "* || " $* " == *" -h "* ]]; then
        grep -E '^#( |$)' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
        return 0
    fi
    invoke_init "$@"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    set -euo pipefail
    main "$@"
fi
