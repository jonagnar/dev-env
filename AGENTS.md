# AGENTS.md — working in this meta-repo

This is a self-contained dev-environment meta-repo. One clone = the whole context.

## Layout
- Root scripts — the tool: `install.sh` (provision), `backup.sh` (age-encrypted
  snapshot), `restore.sh` (decrypt + extract). Standalone bash, no shared lib;
  runs on Linux/WSL and on Windows under Git Bash (winget bootstraps mise there).
- `src/` — your cloned repos (gitignored), flat: projects, notes, infra — anything
  with its own `.git`. Compose-stack repos keep secrets as `*.env.sops` and leave
  live Docker volumes/data untracked per their own `.gitignore`.
- `.config/` — machinery: `mise/core.toml` (core tools), `sops/.sops.yaml`
  (age recipient), `chezmoi/` (shell-init templates). Backups land OUTSIDE the
  repo: `--backup-dir` > `$DEV_BACKUP_DIR` > `~/.config/dev/backup-dir` >
  `~/backups`.

## Rules
- Secrets live in `*.env.sops` (ciphertext) per project; never commit plaintext.
- Add a global tool with `mise use -g <tool>` — keep `.config/mise/core.toml` minimal.
- Every script supports `--help` and `--dry-run`; `restore` prompts unless `--yes`.
- Run `./install.sh` to provision; `./backup.sh` for an encrypted snapshot.
