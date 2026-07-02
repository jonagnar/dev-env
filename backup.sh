#!/usr/bin/env bash
# backup.sh — produce an age-encrypted snapshot of all repos.
# Never prompts (nothing destructive) — run it whenever you want a snapshot.
#   ./backup.sh --dry-run
#   ./backup.sh [--backup-dir DIR]
# Destination (first match wins): --backup-dir > $DEV_BACKUP_DIR >
# ~/.config/dev/backup-dir (install asks once) > ~/backups. Point it INTO your
# sync app's local folder (e.g. Proton Drive on /mnt/c) — the archive is
# ciphertext, so the synced copy is safe; sync apps can't watch WSL paths.

DRY_RUN=0

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

dev_root() { cd "$(dirname "${BASH_SOURCE[0]}")" && pwd; }

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
    local root="$1" cfg="$root/.config/mise/core.toml"
    if command -v cygpath >/dev/null 2>&1; then
        # env vars for native mise.exe need C:/-style paths; PATH entries need
        # MSYS-style ones — convert each accordingly. The shims delegate to
        # mise itself, so the WinGet Links dir must be reachable too.
        cfg="$(cygpath -m "$cfg")"
        local la; la="$(cygpath -u "$LOCALAPPDATA")"
        command -v mise >/dev/null 2>&1 || export PATH="$la/Microsoft/WinGet/Links:$PATH"
        command -v age  >/dev/null 2>&1 || export PATH="$la/mise/shims:$PATH"
    else
        command -v age >/dev/null 2>&1 || export PATH="$HOME/.local/share/mise/shims:$PATH"
    fi
    export MISE_GLOBAL_CONFIG_FILE="${MISE_GLOBAL_CONFIG_FILE:-$cfg}"
}

parse_common_flags() {
    REST_ARGS=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run|--what-if) DRY_RUN=1 ;;
            --yes|-y)            ;;  # accepted for symmetry; backup never prompts
            *)                   REST_ARGS+=("$1") ;;
        esac
        shift
    done
}

# Discover git repos to back up: the meta-repo root plus any git repo directly under src/.
get_dev_repos() {
    local root="$1"
    [[ -d "$root/.git" ]] && printf '%s\n' "$root"
    if [[ -d "$root/src" ]]; then
        local d
        for d in "$root/src"/*/; do
            [[ -d "${d%/}/.git" ]] && printf '%s\n' "${d%/}"
        done
    fi
    return 0
}

# Parse the age recipient(s) from .config/sops/.sops.yaml. NEVER reads the private key.
get_backup_recipients() {
    local root="$1"
    local sops="$root/.config/sops/.sops.yaml"
    [[ -f "$sops" ]] || { err "No .config/sops/.sops.yaml found — run install first."; return 1; }
    local line
    line="$(grep -E '^[[:space:]]*age:' "$sops" | head -n1)"
    [[ -n "$line" ]] || { err ".sops.yaml has no 'age:' recipient."; return 1; }
    line="${line#*age:}"
    line="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^["'\'']//' -e 's/["'\'']$//')"
    local IFS=','
    local r
    for r in $line; do
        r="$(printf '%s' "$r" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        [[ -n "$r" ]] && printf '%s\n' "$r"
    done
}

invoke_backup() {
    parse_common_flags "$@"
    local backup_dir=""
    local i
    for ((i = 0; i < ${#REST_ARGS[@]}; i++)); do
        if [[ "${REST_ARGS[$i]}" == "--backup-dir" ]]; then
            backup_dir="${REST_ARGS[$((i + 1))]:-}"
        fi
    done

    local root; root="$(dev_root)"
    ensure_age "$root"
    [[ -n "$backup_dir" ]] || backup_dir="$(backup_dest)"

    local stamp; stamp="$(date +%Y%m%d-%H%M%S)"
    local staging="${TMPDIR:-/tmp}/devbackup-$stamp"
    # The plaintext tar stays in TMPDIR — only the .age ciphertext ever touches
    # the destination, which is often a sync-watched folder that could upload a
    # transient plaintext file before we shred it.
    local tar_file="${TMPDIR:-/tmp}/dev-backup-$stamp.tar"
    local enc="$backup_dir/dev-backup-$stamp.tar.age"

    phase "Backup -> $enc"

    step "bundle repos" _backup_bundle "$root" "$staging" || return 1
    step "tar staging" _backup_tar "$backup_dir" "$tar_file" "$staging" || return 1
    step "age-encrypt + clean up" _backup_encrypt "$root" "$enc" "$tar_file" "$staging" || return 1

    if [[ "$DRY_RUN" == "1" ]]; then
        info "[dry-run] would write backup: $enc"
    else
        info "Backup written: $enc"
    fi
}

_backup_bundle() {
    local root="$1" staging="$2"
    mkdir -p "$staging"
    local repo name
    while IFS= read -r repo; do
        [[ -n "$repo" ]] || continue
        name="$(basename "$repo")"
        run_native git -C "$repo" bundle create "$staging/$name.bundle" --all || return 1
    done < <(get_dev_repos "$root")
}

_backup_tar() {
    local backup_dir="$1" tar_file="$2" staging="$3"
    mkdir -p "$backup_dir"
    run_native tar -cf "$tar_file" -C "$staging" .
}

_backup_encrypt() {
    local root="$1" enc="$2" tar_file="$3" staging="$4"
    local rc=0
    local -a age_args=()
    local r
    while IFS= read -r r; do
        [[ -n "$r" ]] && age_args+=(-r "$r")
    done < <(get_backup_recipients "$root")
    if [[ ${#age_args[@]} -eq 0 ]]; then
        err "No age recipients resolved — refusing to leave plaintext behind."
        rc=1
    else
        age_args+=(-o "$enc" "$tar_file")
        run_native age "${age_args[@]}" || rc=1
    fi
    # Always shred the plaintext tar + staging, on success OR failure: the
    # destination (often a synced folder) must never retain a plaintext archive.
    rm -f "$tar_file" 2>/dev/null || true
    rm -rf "$staging" 2>/dev/null || true
    return "$rc"
}

main() {
    if [[ " $* " == *" --help "* || " $* " == *" -h "* ]]; then
        grep -E '^#( |$)' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
        return 0
    fi
    invoke_backup "$@"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    set -euo pipefail
    main "$@"
fi
