#!/usr/bin/env bash
# scripts/update.sh — pull the meta-repo, reconcile tools to the core config,
# re-apply host config. Linux port of scripts/update.ps1.
#   ./scripts/update.sh --dry-run
#   ./scripts/update.sh --yes
# On Linux there is no scoop; tool reconciliation is mise-only.
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/verify.sh"   # provides invoke_verify

invoke_update() {
    parse_common_flags "$@"
    local root; root="$(dev_root)"

    phase "Update"
    step "git pull meta-repo" run_native git -C "$root" pull --ff-only || warn "git pull failed (continuing)"

    if confirm "Update installed tools (mise)?"; then
        step "reconcile mise tools" _update_mise "$root" || return 1
    else
        warn "Skipped tool updates."
    fi

    step "re-apply chezmoi" _update_chezmoi "$root" || return 1

    if [[ "$DRY_RUN" != "1" ]]; then
        invoke_verify >/dev/null || true
    fi
}

_update_mise() {
    local root="$1"
    MISE_GLOBAL_CONFIG_FILE="$root/.config/mise/core.toml" run_native mise install || return 1
    MISE_GLOBAL_CONFIG_FILE="$root/.config/mise/core.toml" run_native mise upgrade || return 1
}

_update_chezmoi() {
    local root="$1"
    DEV_ROOT="$root" run_native chezmoi apply --source "$root/.config/chezmoi" || return 1
}

main() {
    if [[ " $* " == *" --help "* || " $* " == *" -h "* ]]; then
        grep -E '^#( |$)' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
        return 0
    fi
    invoke_update "$@"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    set -euo pipefail
    main "$@"
fi
