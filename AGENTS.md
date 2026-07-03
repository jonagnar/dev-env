# AGENTS.md — working in this meta-repo

This is a self-contained dev-environment meta-repo. One clone = the whole context.

## Layout
- Root scripts — the tool: `install.sh` (provision), `backup.sh` (age-encrypted
  snapshot), `restore.sh` (decrypt + extract). Standalone bash, no shared lib;
  runs on Linux/WSL and on Windows under Git Bash (winget bootstraps mise there).
- `src/` — your cloned repos (gitignored), flat: projects, notes, infra — anything
  with its own `.git`. Exception: `src/demo-api/` is committed as the reference
  example of mise+sops multi-tenant secrets wiring (`mise.<tenant>.toml` +
  `secrets/*.env.json` ciphertext). Compose-stack repos keep secrets as
  `*.env.sops` and leave live Docker volumes/data untracked per their own
  `.gitignore`.
- `.config/` — machinery: `mise/core.toml` (core tools), `sops/.sops.yaml.tmpl`
  (seed for the age recipient), `chezmoi/` (shell-init + gitconfig templates,
  global gitignore, gitleaks pre-commit hook template). Backups land OUTSIDE the
  repo: `--backup-dir` > `$DEV_BACKUP_DIR` > `~/.config/dev/backup-dir` >
  `~/backups`.

## Commands
No build, lint, or test suite — three standalone bash scripts. Verify changes with:
- `bash -n <script>.sh` — syntax check.
- `./install.sh --dry-run` · `./backup.sh --dry-run` · `./restore.sh --dry-run` —
  exercise the full flow with zero side effects; this is the closest thing to a test.
- `./<script>.sh --help` — prints the script's leading `#` comment block (see below).

## Script architecture (read before editing the scripts)
- **Deliberately standalone, deliberately duplicated.** There is no shared lib:
  helpers (`info/warn/err/phase`, `run_native`, `step`, `parse_common_flags`,
  `dev_root`, `ensure_age`, `backup_dest`) are copy-pasted across the three
  scripts so each survives alone (e.g. restore.sh on a bare machine). If you
  change a helper, make the same change in every script that carries it — and
  don't "fix" the duplication by extracting a lib.
- **The header comment IS the help.** `--help` greps the leading `# ` block of
  the script, so those comments are user-facing documentation — keep usage
  lines there accurate.
- **Dry-run is structural.** Every side-effecting action goes through
  `step "name" cmd args...` (prints `[dry-run] would: name` and skips) and
  prompts go through `confirm` (dry-run prints the would-prompt). New actions
  must use these wrappers, never a raw command.
- `set -euo pipefail` + `main "$@"` run only under the `BASH_SOURCE` guard, so
  scripts can be sourced to test individual functions.
- **Windows/Git Bash path rules** (the subtlest part): MSYS converts *command
  arguments* to C:/-style for native .exe tools but NOT *environment variables* —
  anything exported for mise.exe/chezmoi.exe (e.g. `MISE_GLOBAL_CONFIG_FILE`,
  `DEV_ROOT`) must go through `cygpath -m` (the `to_native` helper); PATH
  entries, conversely, must stay MSYS-style (`cygpath -u`). mise itself lives in
  the WinGet Links dir; its tool shims in `$LOCALAPPDATA/mise/shims` — both must
  be added to PATH in non-interactive shells (`ensure_age`).
- The backup-destination resolution chain is implemented twice (backup.sh and
  restore.sh `backup_dest`) — keep them identical.

## Rules
- Secrets live in `*.env.sops` or sops-encrypted `secrets/*.env.json`
  (ciphertext) per project; never commit plaintext.
- `.config/sops/.sops.yaml` is rendered ONCE from the `.tmpl` by install and is
  gitignored — never re-render or overwrite it; recipients added since would be
  silently dropped.
- Dotfile integration is append-one-line-if-missing only (`.bashrc`,
  `.bash_profile`, `.gitconfig`) — never rewrite a user's file.
- Everything is LF: `.gitattributes` pins `eol=lf` because CRLF in a `.sh` or a
  bash-consumed template breaks with `$'\r': command not found`. Don't introduce
  CRLF, and keep new binary extensions listed there.
- Add a global tool with `mise use -g <tool>` — keep `.config/mise/core.toml`
  minimal (only what the scripts themselves need: sops, age, chezmoi, gitleaks).
- Every script supports `--help` and `--dry-run`; `restore` prompts unless
  `--yes`; `backup` never prompts.
