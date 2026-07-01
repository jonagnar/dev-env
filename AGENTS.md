# AGENTS.md — working in this meta-repo

This is a self-contained dev-environment meta-repo. One clone = the whole context.

## Layout
- `scripts/` — the tool. Five verbs (`init`, `verify`, `update`, `backup`, `restore`),
  each a `.ps1` (Windows) + `.sh` (Linux/WSL) port, sharing `scripts/lib/common.*`.
- `ops/` — your cloned repos (gitignored): projects plus `ops/notes` (Obsidian vault),
  `ops/resources` (shared SDD assets + render tools), and `ops/infra` — homelab
  infra-as-code (`WAAAGH/infra`): compose stacks + `*.env.sops` secrets; live Docker
  volumes/data untracked per its own `.gitignore`.
- `tools/` — `bin/` on PATH (gitignored); `manifest.md` documents GUI apps.
- `backups/` — age-encrypted snapshots (gitignored).
- `.config/` — machinery: `mise/core.toml` (core tools), `sops/.sops.yaml`
  (age recipient), `chezmoi/` (shell-init templates).

## Rules
- Secrets live in `*.env.sops` (ciphertext) per project; never commit plaintext.
- Add a global tool with `mise use -g <tool>` — keep `.config/mise/core.toml` minimal.
- Every script supports `--help` and `-WhatIf`/`--dry-run`; destructive verbs prompt unless `-Yes`.
- Run `scripts/verify.ps1` to confirm machine health.
