#!/usr/bin/env bash
# install.sh — provision or refresh this machine for the dev-environment.
#   ./install.sh --dry-run    # preview
#   ./install.sh --yes        # provision non-interactively
#
# Notes:
#   * No root required. Preflight only warns (git missing / no network); under
#     --dry-run warnings never abort.
#   * mise is bootstrapped via `curl https://mise.run | sh` (user-scope
#     ~/.local/bin); git is only warned about (no auto-sudo).
#   * Backups are manual — run ./backup.sh when you want a snapshot. If you
#     want them automatic, schedule it yourself (cron/systemd/whatever).

DRY_RUN=0
ASSUME_YES=0

info()  { printf '%s\n' "$*"; }
warn()  { printf 'WARN: %s\n' "$*" >&2; }
err()   { printf 'ERROR: %s\n' "$*" >&2; }
phase() { printf '\n== %s ==\n' "$*"; }

# Run "$@"; on non-zero exit print an error and return that status.
run_native() {
    "$@"; local rc=$?
    [[ $rc -ne 0 ]] && err "Command failed (exit $rc): $*"
    return $rc
}

# Dry-run-aware step: under --dry-run print the would-message and skip.
step() {
    local name="$1"; shift
    if [[ "$DRY_RUN" == "1" ]]; then printf '  [dry-run] would: %s\n' "$name"; return 0; fi
    printf '  -> %s\n' "$name"; "$@"
}

dev_root()     { cd "$(dirname "${BASH_SOURCE[0]}")" && pwd; }
age_key_path() { printf '%s/.config/sops/age/keys.txt\n' "$HOME"; }

parse_common_flags() {
    REST_ARGS=(); SHOW_HELP=0
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
    # umask 077 in a subshell so every dir/file created here is private from birth.
    # NOTE: no `local` inside the ( ) subshell — it's not a function body; `pub` is plain.
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

_mise_install() {
    local root="$1"
    local cfg="$root/.config/mise/core.toml"
    MISE_GLOBAL_CONFIG_FILE="$cfg" run_native mise trust "$cfg"
    MISE_GLOBAL_CONFIG_FILE="$cfg" run_native mise install
}

_chezmoi_apply() {
    local root="$1"
    DEV_ROOT="$root" run_native chezmoi init --apply --source "$root/.config/chezmoi"
}

# Hook ~/.config/dev/shell-init.sh into ~/.bashrc with ONE appended line.
# Never rewrites .bashrc — append-if-missing only, so user config is untouched.
_hook_bashrc() {
    local hook='[ -f "$HOME/.config/dev/shell-init.sh" ] && . "$HOME/.config/dev/shell-init.sh"'
    local rc="$HOME/.bashrc"
    if [[ -f "$rc" ]] && grep -qF 'config/dev/shell-init.sh' "$rc"; then
        info "shell-init hook already in ~/.bashrc"
        return 0
    fi
    printf '\n# dev meta-repo shell init (installed by install.sh)\n%s\n' "$hook" >> "$rc"
}

invoke_install() {
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
    step "mise install core (sops age chezmoi gitleaks)" _mise_install "$root" || return 1
    # Put the just-installed mise tools on PATH for the rest of THIS process —
    # chezmoi (Phase 3) and age-keygen (Phase 4) run before any new shell activates mise.
    if [[ "${DRY_RUN:-0}" -ne 1 ]] && command -v mise >/dev/null 2>&1; then
        eval "$(MISE_GLOBAL_CONFIG_FILE="$root/.config/mise/core.toml" mise env -s bash 2>/dev/null)" || true
    fi

    phase "Phase 2 — Skeleton"
    local d
    for d in ops backup; do
        step "ensure $d/" ensure_dir "$root/$d" || return 1
    done

    phase "Phase 3 — Host config"
    step "chezmoi init --apply" _chezmoi_apply "$root" || return 1
    step "hook shell-init into ~/.bashrc (append-only)" _hook_bashrc || return 1

    phase "Phase 4 — Secrets"
    step "generate work age key + write recipient" \
        new_dev_age_key "$(age_key_path)" \
        "$root/.config/sops/.sops.yaml.tmpl" \
        "$root/.config/sops/.sops.yaml" || return 1
    info "Store the PRIVATE key (~/.config/sops/age/keys.txt) in your password manager (Bitwarden/Vaultwarden) + offline."

    info ""
    info "Done — provisioning complete. Run ./backup.sh whenever you want a snapshot."
}

main() {
    if [[ " $* " == *" --help "* || " $* " == *" -h "* ]]; then
        grep -E '^#( |$)' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
        return 0
    fi
    invoke_install "$@"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    set -euo pipefail
    main "$@"
fi
