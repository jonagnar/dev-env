# ~/dev — AI working instructions

Self-hosted, backup-first, cross-platform dev environment. **WSL `~/dev` is the canonical
source of truth.** A Windows native layer (`c:\dev\` for `notes/ tools/ resources/`) is
planned but deferred.

**Resuming? Read `notes/dev-environment.md` (vision) and `README.md` (spec + build-log) first.**

## Layout (all lowercase, identical cross-platform)
- `code/` — repos, flat, Forgejo-hosted (WSL-only). `_config/` = chezmoi host config, `_sandbox/` = disposable (`_` sorts them above the projects).
- `ops/` — self-hosted services & automation. `ops/docker/<svc>/` for dockerized services; `ops/scripts/` for automation.
- `notes/` — Obsidian vault (Forgejo repo): `manuals/ cheatsheets/ instructions/ logs/ projects/`.
- `tools/` — portable tools (`bin/` on PATH); binaries are re-downloadable, only the manifest is backed up.
- `resources/` — static assets + SDD: `resources/<project>/{documents,specs,plans}`.
- `tmp/` — scratch, nuke anytime.

## Conventions
- **Secrets:** sops + age + direnv. One age key (`~/.config/sops/age/keys.txt`, in Bitwarden) decrypts every `.env.sops`. Never commit plaintext secrets.
- **Versions:** `mise` per repo. **Package manager:** pnpm pinned via `packageManager` (avoid pnpm 11.x).
- **Remotes:** `origin` = Forgejo (`ssh://git@localhost:2222/jonnxor/…`) — the only remote in a clone. For `jonnxor.is`, Forgejo push-mirrors **server-side** to GitHub, which deploys the LIVE Vercel site. Push to `origin` and let the mirror fan out — **don't add a direct `github` remote or push to GitHub from a clone** (it bypasses Forgejo straight to prod).
- **Branch flow (`jonnxor.is`):** feature → `preview` → `main`. `preview` deploys to **preview.jonnxor.is**; `main` deploys to **production** (jonnxor.is). Open feature PRs against **`preview`**, never straight to `main`.
- **PRs vs direct push:** open PRs for the **project repos** (`code/<project>` — e.g. `jonnxor.is`, `silver-remaster`), **`ops`**, and **`_config`** (`config`). Push **directly to `main`** for **`dev`** (env docs, `resources/`, `tools/`) and **`notes`** (the vault) — low-ceremony, no PR. All six stay Forgejo repos regardless: that membership is what feeds the Forgejo→Proton backup, so do **not** drop a repo without a replacement file-level backup.

## The SDD cycle (do this every cycle)
After each spec-driven-development cycle, **update + commit + push**:
1. **docs** — the touched repo's `docs/` (README/RELEASE/CHANGELOG).
2. **kb** — relevant `notes/` (manuals, cheatsheets, instructions, daily `logs/`).
3. **resources** — `resources/<project>/{documents,specs,plans}` (the durable record).
4. **scripts** — any new/changed `ops/scripts/` automation.
**Specs/plans live in `code/<project>/.planning/` while active, promoted to `resources/<project>/` when finished — never in `notes/` (that's knowledge-base only). Promotion *renders the `.md` to PDF* via `tools/md2pdf` — `resources/` holds PDFs, `.planning/` keeps the `.md` source.** Env-level work with no code repo (e.g. the dev-env itself) goes straight to `resources/<name>/`.

**Promotion timing.** When a cycle's code reaches the **PR stage**, render its `.planning/` design+plan to PDF (design → `resources/<project>/specs/`, plan → `resources/<project>/plans/`) and **commit + push them directly to the `dev` repo's `main`** — the `dev` repo does **not** use PRs. So a cycle yields one PR (the project code, against `preview`) plus a direct push of the rendered SDD to `dev`. This may be done automatically once the code PR exists.

## Backup / house-fire rule
Back up what you *made* and can't re-fetch. Everything irreplaceable converges on Forgejo →
encrypted dump → Proton (daily `forgejo-backup.timer`). Disaster runbook: `ops/RESTORE.md`.
Fresh machine: `ops/bootstrap.sh`. The age key is the only break-glass secret (Bitwarden).
