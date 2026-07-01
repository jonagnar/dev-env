#!/usr/bin/env bash
# restore.sh — decrypt a dev-backup-*.tar.age archive and extract to staging.
#   ./restore.sh --dry-run
#   ./restore.sh --yes [--archive FILE] [--backup-dir DIR]
# Looks where backup.sh writes: --backup-dir > $DEV_BACKUP_DIR >
# ~/.config/dev/backup-dir (install asks once) > ~/backups.

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

# Return 0 (yes) if --yes; under --dry-run print the would-prompt and return 1.
confirm() {
    local message="$1"
    [[ "$ASSUME_YES" == "1" ]] && return 0
    if [[ "$DRY_RUN" == "1" ]]; then printf '  [dry-run] would prompt: %s\n' "$message"; return 1; fi
    local answer; read -r -p "$message [y/N] " answer
    [[ "$answer" =~ ^([yY]|[yY][eE][sS])$ ]]
}

dev_root()     { cd "$(dirname "${BASH_SOURCE[0]}")" && pwd; }
age_key_path() { printf '%s/.config/sops/age/keys.txt\n' "$HOME"; }

# Destination preference: $DEV_BACKUP_DIR > ~/.config/dev/backup-dir > ~/backups.
backup_dest() {
    local dest=""
    if [[ -n "${DEV_BACKUP_DIR:-}" ]]; then dest="$DEV_BACKUP_DIR"
    elif [[ -f "$HOME/.config/dev/backup-dir" ]]; then dest="$(head -n1 "$HOME/.config/dev/backup-dir")"
    else dest="$HOME/backups"; fi
    printf '%s\n' "${dest/#\~/$HOME}"   # tolerate a hand-written ~/ in the pref
}

# age comes from mise; outside an interactive shell (cron, plain bash -c)
# mise isn't activated and its shims can't pick a version without the repo's
# core config. Wire both up if age isn't already resolvable.
ensure_age() {
    local root="$1"
    export MISE_GLOBAL_CONFIG_FILE="${MISE_GLOBAL_CONFIG_FILE:-$root/.config/mise/core.toml}"
    command -v age >/dev/null 2>&1 || export PATH="$HOME/.local/share/mise/shims:$PATH"
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

# Newest dev-backup-*.tar.age in backup_dir, by modification time.
get_latest_archive() {
    local backup_dir="$1"
    local latest=""
    latest="$(find "$backup_dir" -maxdepth 1 -name 'dev-backup-*.tar.age' -printf '%T@ %p\n' 2>/dev/null \
        | sort -rn | head -n1 | cut -d' ' -f2-)"
    [[ -n "$latest" ]] && printf '%s\n' "$latest"
    return 0
}

invoke_restore() {
    parse_common_flags "$@"
    local archive="" backup_dir=""
    local i
    for ((i = 0; i < ${#REST_ARGS[@]}; i++)); do
        case "${REST_ARGS[$i]}" in
            --archive)    archive="${REST_ARGS[$((i + 1))]:-}" ;;
            --backup-dir) backup_dir="${REST_ARGS[$((i + 1))]:-}" ;;
        esac
    done

    local root; root="$(dev_root)"
    ensure_age "$root"
    [[ -n "$backup_dir" ]] || backup_dir="$(backup_dest)"
    [[ -n "$archive" ]] || archive="$(get_latest_archive "$backup_dir")"
    if [[ -z "$archive" ]]; then
        err "No backups found in $backup_dir. Nothing to restore."
        return 1
    fi

    local stamp; stamp="$(date +%Y%m%d-%H%M%S)"
    local staging="$root/restore-$stamp"
    local tar_file="${TMPDIR:-/tmp}/restore-$stamp.tar"
    local key_path; key_path="$(age_key_path)"

    phase "Restore $archive -> $staging"
    if ! confirm "Restore '$archive' into '$staging'?"; then
        warn "Aborted."
        return 0
    fi

    step "decrypt archive" run_native age -d -i "$key_path" -o "$tar_file" "$archive" || return 1
    step "extract to staging" _restore_extract "$staging" "$tar_file" || return 1
    info "Restored bundles are in $staging. To rebuild a repo: git clone <name>.bundle <target>."
}

_restore_extract() {
    local staging="$1" tar_file="$2"
    mkdir -p "$staging"
    if ! run_native tar -xf "$tar_file" -C "$staging"; then
        rmdir "$staging" 2>/dev/null || true   # don't litter empty staging dirs on failure
        return 1
    fi
    rm -f "$tar_file" 2>/dev/null || true
}

main() {
    if [[ " $* " == *" --help "* || " $* " == *" -h "* ]]; then
        grep -E '^#( |$)' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
        return 0
    fi
    invoke_restore "$@"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    set -euo pipefail
    main "$@"
fi
