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

# Native-tool-friendly path: MSYS converts command ARGS for .exe tools but NOT
# env vars, so anything exported for mise.exe/chezmoi.exe must be C:/-style on
# Git Bash. No-op on Linux/WSL.
to_native() {
    if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s\n' "$1"; fi
}

parse_common_flags() {
    REST_ARGS=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run|--what-if) DRY_RUN=1 ;;
            --yes|-y)            ASSUME_YES=1 ;;
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

# Bootstrap mise user-scope.
#   Linux/WSL:          curl https://mise.run | sh   -> ~/.local/bin
#   Windows (Git Bash): winget install jdx.mise      -> WinGet Links dir
# (mise.run's installer refuses MINGW — Windows uses the native build.)
ensure_mise() {
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*)
            # winget puts the exe alias in its Links dir, which only lands on
            # PATH in NEW shells — check there before (re)installing.
            local links; links="$(cygpath -u "$LOCALAPPDATA")/Microsoft/WinGet/Links"
            if [[ ! -x "$links/mise.exe" ]]; then
                run_native winget install -e --id jdx.mise --accept-source-agreements --accept-package-agreements || return 1
            fi
            export PATH="$links:$PATH"
            ;;
        *)
            run_native bash -c 'curl -fsSL https://mise.run | sh' || return 1
            export PATH="$HOME/.local/bin:$PATH"
            ;;
    esac
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
        # Render the recipient file only on first run — it may have gained
        # extra recipients since, and re-rendering would silently drop them.
        if [[ ! -f "$sops_config" ]]; then
            pub="$(run_native age-keygen -y "$key_path")" || exit 1
            pub="${pub//[$'\r\n']/}"
            ensure_dir "$(dirname "$sops_config")"
            sed "s|REPLACE_WITH_AGE_PUBLIC_KEY|$pub|" "$sops_tmpl" > "$sops_config"
        else
            info ".sops.yaml already rendered — keeping it (recipients preserved)."
        fi
    ) || return 1
}

_mise_install() {
    local root="$1"
    local cfg; cfg="$(to_native "$root/.config/mise/core.toml")"
    MISE_GLOBAL_CONFIG_FILE="$cfg" run_native mise trust "$cfg"
    MISE_GLOBAL_CONFIG_FILE="$cfg" run_native mise install
}

_chezmoi_apply() {
    local root="$1"
    # --yes makes this truly non-interactive: chezmoi otherwise prompts when a
    # managed target changed on disk since it last wrote it.
    local -a extra=()
    [[ "$ASSUME_YES" == "1" ]] && extra=(--force)
    DEV_ROOT="$(to_native "$root")" run_native chezmoi init --apply "${extra[@]}" --source "$root/.config/chezmoi"
}

# Wire the chezmoi-managed gitconfig into ~/.gitconfig with ONE include —
# never rewrites the user's file (identity, safe.directory, editor survive;
# anything they set after the include wins over ours).
_hook_gitconfig() {
    if git config --global --get-all include.path 2>/dev/null | grep -q 'config/dev/gitconfig'; then
        info "gitconfig include already present"
        return 0
    fi
    run_native git config --global --add include.path "~/.config/dev/gitconfig"
}

# Git identity is personal — this repo ships none. Warn if it's missing.
_check_git_identity() {
    local n e
    n="$(git config user.name 2>/dev/null || true)"
    e="$(git config user.email 2>/dev/null || true)"
    if [[ -z "$n" || -z "$e" ]]; then
        warn "git identity not set — commits will fail until you run:"
        warn "  git config --global user.name  'Your Name'"
        warn "  git config --global user.email 'you@example.com'"
    else
        info "git identity: $n <$e> (yours, untouched)"
    fi
}

# Ask once where backups should go; persist to ~/.config/dev/backup-dir.
# backup.sh/restore.sh read it (overridable via $DEV_BACKUP_DIR / --backup-dir).
# Non-interactive (--yes / no tty): defaults to ~/backups without asking.
_backup_pref() {
    local pref="$HOME/.config/dev/backup-dir"
    if [[ -f "$pref" ]]; then
        info "backup destination: $(head -n1 "$pref") (already set — edit $pref to change)"
        return 0
    fi
    local default="$HOME/backups" answer=""
    if [[ "$ASSUME_YES" == "1" || ! -t 0 ]]; then
        answer="$default"
    else
        read -r -p "Where should backups go? (tip: a folder your sync app watches) [$default] " answer
        [[ -n "$answer" ]] || answer="$default"
        answer="${answer/#\~/$HOME}"
    fi
    ensure_dir "$(dirname "$pref")"
    printf '%s\n' "$answer" > "$pref"
    info "backup destination: $answer (saved to $pref)"
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
        step "bootstrap mise (winget on Windows, mise.run elsewhere)" ensure_mise || return 1
    else
        info "mise already present."
    fi
    step "mise install core (sops age chezmoi gitleaks)" _mise_install "$root" || return 1
    # Put the just-installed mise tools on PATH for the rest of THIS process —
    # chezmoi (Phase 3) and age-keygen (Phase 4) run before any new shell activates mise.
    if [[ "${DRY_RUN:-0}" -ne 1 ]] && command -v mise >/dev/null 2>&1; then
        # every later mise/shim invocation needs to know about the core config
        export MISE_GLOBAL_CONFIG_FILE="$(to_native "$root/.config/mise/core.toml")"
        if command -v cygpath >/dev/null 2>&1; then
            # `mise env` emits a Windows-style PATH that clobbers the MSYS one
            # (goodbye /usr/bin) — put mise's shims on PATH instead.
            export PATH="$(cygpath -u "$LOCALAPPDATA")/mise/shims:$PATH"
        else
            eval "$(mise env -s bash 2>/dev/null)" || true
        fi
    fi

    phase "Phase 2 — Skeleton"
    step "ensure src/" ensure_dir "$root/src" || return 1

    phase "Phase 3 — Host config"
    step "chezmoi init --apply" _chezmoi_apply "$root" || return 1
    step "hook shell-init into ~/.bashrc (append-only)" _hook_bashrc || return 1
    step "hook gitconfig include (append-only)" _hook_gitconfig || return 1
    step "check git identity (yours, never ours)" _check_git_identity || return 1

    phase "Phase 4 — Secrets"
    step "generate work age key + write recipient" \
        new_dev_age_key "$(age_key_path)" \
        "$root/.config/sops/.sops.yaml.tmpl" \
        "$root/.config/sops/.sops.yaml" || return 1
    info "Store the PRIVATE key (~/.config/sops/age/keys.txt) in your password manager (Bitwarden/Vaultwarden) + offline."

    phase "Phase 5 — Backup destination"
    step "record backup destination (asked once)" _backup_pref || return 1

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
