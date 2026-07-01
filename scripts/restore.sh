#!/usr/bin/env bash
# scripts/restore.sh — decrypt a backups/*.tar.age archive and extract to staging.
# Linux port of scripts/restore.ps1.
#   ./scripts/restore.sh --dry-run
#   ./scripts/restore.sh --yes [--archive FILE] [--backup-dir DIR]
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

# Newest dev-backup-*.tar.age in BackupDir, by modification time.
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
    [[ -n "$backup_dir" ]] || backup_dir="$root/backups"
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
    run_native tar -xf "$tar_file" -C "$staging" || return 1
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
