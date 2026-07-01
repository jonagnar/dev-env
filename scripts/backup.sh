#!/usr/bin/env bash
# scripts/backup.sh — produce an age-encrypted snapshot of all repos into backups/.
# Linux port of scripts/backup.ps1.
#   ./scripts/backup.sh --dry-run
#   ./scripts/backup.sh --yes [--backup-dir DIR]
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

# Discover git repos to back up: the meta-repo root plus any git repo directly
# under ops/.
get_dev_repos() {
    local root="$1"
    [[ -d "$root/.git" ]] && printf '%s\n' "$root"
    if [[ -d "$root/ops" ]]; then
        local d
        for d in "$root/ops"/*/; do
            [[ -d "${d%/}/.git" ]] && printf '%s\n' "${d%/}"
        done
    fi
    return 0
}

# Parse the age recipient(s) from .config/sops/.sops.yaml. NEVER reads the
# private key. Emits one recipient per line.
get_backup_recipients() {
    local root="$1"
    local sops="$root/.config/sops/.sops.yaml"
    [[ -f "$sops" ]] || { err "No .config/sops/.sops.yaml found — run init first."; return 1; }
    local line
    line="$(grep -E '^[[:space:]]*age:' "$sops" | head -n1)"
    [[ -n "$line" ]] || { err ".sops.yaml has no 'age:' recipient."; return 1; }
    # strip "age:" prefix and surrounding quotes/space, split on commas
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
    # --backup-dir DIR consumed from REST_ARGS
    local i
    for ((i = 0; i < ${#REST_ARGS[@]}; i++)); do
        if [[ "${REST_ARGS[$i]}" == "--backup-dir" ]]; then
            backup_dir="${REST_ARGS[$((i + 1))]:-}"
        fi
    done

    local root; root="$(dev_root)"
    [[ -n "$backup_dir" ]] || backup_dir="$root/backups"

    local stamp; stamp="$(date +%Y%m%d-%H%M%S)"
    local staging="${TMPDIR:-/tmp}/devbackup-$stamp"
    local tar_file="$backup_dir/dev-backup-$stamp.tar"
    local enc="$tar_file.age"
    local key_path; key_path="$(age_key_path)"

    phase "Backup -> $enc"

    step "bundle repos" _backup_bundle "$root" "$staging" || return 1
    step "tar staging" _backup_tar "$backup_dir" "$tar_file" "$staging" || return 1
    step "age-encrypt + clean up" _backup_encrypt "$root" "$enc" "$tar_file" "$staging" || return 1

    info "Backup written: $enc"
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
    local -a age_args=()
    local r
    while IFS= read -r r; do
        [[ -n "$r" ]] && age_args+=(-r "$r")
    done < <(get_backup_recipients "$root")
    age_args+=(-o "$enc" "$tar_file")
    run_native age "${age_args[@]}" || return 1
    rm -f "$tar_file" 2>/dev/null || true
    rm -rf "$staging" 2>/dev/null || true
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
