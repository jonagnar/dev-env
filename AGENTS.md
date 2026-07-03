# AGENTS.md — working in this meta-repo

Self-contained dev-environment meta-repo. One clone = the whole context: three
standalone bash scripts that provision a machine (`install.sh`), snapshot every
repo into an age-encrypted archive (`backup.sh`), and decrypt/stage it back
(`restore.sh`). No build step, no dependencies beyond bash + git — everything
else (sops, age, chezmoi, gitleaks) is installed by `install.sh` via mise.

## Commands
- `./install.sh --dry-run` / `./backup.sh --dry-run` / `./restore.sh --dry-run`
  — preview every step with no side effects; the primary way to verify changes.
- `bash -n <script>` — syntax check. There is no test suite or linter config.
- `./<script> --help` — prints the script's leading `#` comment block (via
  grep), so the header comment IS the help text; update it when changing flags.
- A real (non-dry-run) `install.sh` mutates `$HOME` (dotfiles, age key, mise
  tools) — don't run it just to test a change.

## Script architecture
- The three scripts are deliberately standalone — no shared lib. Helpers
  (`info/warn/err/phase`, `run_native`, `step`, `parse_common_flags`,
  `dev_root`, `backup_dest`, `ensure_age`) are duplicated per script; a change
  to one copy must be mirrored in the others.
- Each script ends with a `[[ "${BASH_SOURCE[0]}" == "${0}" ]]` guard:
  `set -euo pipefail` applies only when executed, so a script can be sourced to
  test individual functions.
- Cross-platform Linux/WSL + native Windows Git Bash; `command -v cygpath` is
  the Windows detector. On Git Bash: env vars consumed by native `.exe` tools
  (mise, chezmoi) need `C:/`-style paths (`cygpath -m`, see `to_native`), while
  PATH entries need MSYS-style (`cygpath -u`); mise is bootstrapped via winget
  (mise.run refuses MINGW), and its exe lands in the WinGet Links dir, which is
  only on PATH in new shells.
- `.gitattributes` pins LF for everything — CRLF silently breaks the scripts
  under bash.

## Layout
- `src/` — your cloned repos, flat, gitignored — EXCEPT `src/demo-api`, which
  is committed on purpose (`.gitignore` whitelists it) as the reference example
  of the secrets pattern: `.sops.yaml` (recipients) + `mise.toml` /
  `mise.<tenant>.toml` (env wiring, selected via `MISE_ENV=<tenant>`) +
  `secrets/*.env.json` (sops ciphertext, safe to commit).
- `.config/mise/core.toml` — core toolchain only; add personal tools with
  `mise use -g <tool>`, don't grow this file.
- `.config/sops/.sops.yaml` is rendered ONCE from `.sops.yaml.tmpl` by install
  and is gitignored; never re-render it — recipients added since would be
  silently dropped. `backup.sh` parses its `age:` line for encryption
  recipients (never reads the private key).
- `.config/chezmoi/` — host-config templates applied to `$HOME`
  (`~/.config/dev/shell-init.sh`, `~/.config/dev/gitconfig`, global gitignore,
  gitleaks pre-commit template hook).
- Backups land OUTSIDE the repo: `--backup-dir` > `$DEV_BACKUP_DIR` >
  `~/.config/dev/backup-dir` > `~/backups`.

## Invariants — don't break these
- Secrets in git are ciphertext only (`secrets/*.env.{json,yaml,toml}` for
  mise-native, `*.env.sops` for compose stacks); plaintext `.env` is blocked by
  gitignore at every layer. Never commit plaintext.
- `backup.sh`: the plaintext tar exists only in `$TMPDIR` and is shredded on
  success AND failure — the destination (often a sync-watched folder) must only
  ever see ciphertext. It refuses to encrypt with zero recipients, and never
  prompts.
- `install.sh` is idempotent and edits user dotfiles append-only, one line each
  (`.bashrc` hook, `.bash_profile` → `.bashrc` chain, gitconfig include) — it
  never rewrites an existing user file.
- Every script supports `--help` and `--dry-run`; `restore.sh` prompts unless
  `--yes`.
