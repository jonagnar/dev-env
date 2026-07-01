# ~/dev — development environment

A cross-platform, self-hosted, backup-first dev environment. Lowercase names everywhere so
it's identical on Linux and Windows. Guiding principle: **own your tools, keep one copy
off-site, and make a fresh machine reproducible from `git clone`.**

## Structure

```
~/dev/   (or c:\dev\)        cross-platform dev root · all lowercase · itself a thin meta-repo (`dev`)
│
├─ CLAUDE.md                AI working instructions + the SDD-cycle rule
│
├─ code/                    every repo you own — flat, Forgejo-hosted, Proton-backed (WSL-only)
│  ├─ _config/               global host config (chezmoi) — `_` sorts it above the projects
│  ├─ _sandbox/              experiments + cloned repos — disposable, not backed up
│  ├─ jonnxor.is/            the personal site (Astro · Directus · .NET 10 API) — src/ tests/ docs/
│  ├─ silver-remaster/       Godot learning project (original game assets gitignored)
│  └─ <project>/             carries its own mise.toml · tests/ · docs/ · .env.example · .env.sops
│
├─ ops/                     self-hosted services + automation — its own repo (+ bootstrap.sh · RESTORE.md)
│  ├─ docker/                dockerized services, one dir each
│  │  ├─ forgejo/             git server + CI (Forgejo Actions) — the hub everything backs up through
│  │  ├─ caddy/               local prod-preview proxy (:8080)
│  │  └─ vaultwarden/ traefik/ coolify/ grafana/ prometheus/ loki/ uptime-kuma/ glitchtip/   (planned stubs)
│  └─ scripts/               automation: backup.sh · backup-resources.sh · systemd/ (backup units)
│
├─ notes/                   Obsidian vault — its own repo in Forgejo
│  ├─ manuals/ cheatsheets/ instructions/ logs/   knowledge base
│  └─ projects/              per-project working docs / planning
│
├─ tools/                   portable tools (tools/bin on PATH) — binaries re-downloadable, manifest backed up
│  └─ bruno/ sqlite/ <tool>/
│
├─ resources/               static assets + SDD — Proton-backed
│  ├─ _fonts/ _images/ <type>/             heavy assets (rsync → Proton)
│  └─ <project>/{documents,specs,plans}  durable SDD record (text git-backed)
│
└─ tmp/                     disposable scratch — nuke anytime
```

## Conventions
- **All lowercase**, cross-platform (Linux + Windows).
- **`code/` is flat**; clones + experiments live in `_sandbox/`.
- **`code/_config`** is the global host layer (chezmoi); **project rules stay inside each repo**. (`_config`/`_sandbox` are underscore-prefixed so they sort above the project repos.)
- **Versions:** `mise` per repo. **Dev containers opt-in** for genuinely complex envs.
- **Forgejo is the hub; Proton is the single off-site** (Drive for files, Bitwarden for break-glass).
- **Backup rule:** back up what you *made* and can't re-fetch; skip what's re-creatable.

## Secrets — sops + age (no server)
- Secrets are encrypted in the repo (`.env.sops`); `.env.example` documents the names.
- One **age key** (`~/.config/sops/age/keys.txt`, mode 600) decrypts every repo.
- **direnv** auto-loads decrypted env on `cd` (after `direnv allow`). Pull-&-run.
- Safety net: a **global gitignore** blocks plaintext secrets in every repo; **gitleaks**
  is installed for a pre-commit guard.
- **Root of trust:** the age private key — back it up to Bitwarden + offline. Never in git.
- Upgrade path: stand up **Infisical** in `ops/` if central rotation/audit is ever wanted.

## Testing (per repo)
- `code/<project>/tests/`. Pyramid: **unit** → **integration** → **E2E (Playwright)**.
- Surfaces: pre-commit (fast unit + lint + gitleaks) → local (mise/devcontainer) → Forgejo Actions (CI).
- TDD the core + bug-fix-first; spike-first in `_sandbox/`.

## Docs & deploys
- Per-repo `docs/` via **Material for MkDocs**, built by CI, served by the proxy (self-hosted github.io).
- **Coolify** (in `ops/`): git push → build → per-branch preview URLs → auto-HTTPS. The Vercel experience, self-hosted.

## Observability — monitoring ≠ logging (in `ops/`, deferred until deployed)
- **Monitoring** (is it healthy now?): Prometheus + Grafana · Uptime Kuma · GlitchTip.
- **Logging** (what happened?): Loki + Grafana; structured JSON to stdout → Docker → Loki.
- Grafana is one pane of glass for both. Privacy-first analytics via Umami.
- Logs aren't backed up (retention rolloff) and never contain secrets/PII.

## Backup — the "house fire" rule

| Bucket | Off-site copy | Why |
|---|---|---|
| `code/` (incl. `_config/`) | Forgejo → Proton | source + **encrypted** secrets (ciphertext) |
| `code/_sandbox/` | — | re-creatable |
| `notes/` | Forgejo → Proton (it's a repo) | irreplaceable |
| `ops/*` | Forgejo → Proton; live data via own dumps | configs irreplaceable; containers rebuildable |
| `resources/` | Proton (rsync) | large, partly irreplaceable |
| `tools/` | a manifest, not binaries | re-downloadable |
| `tmp/` | — | disposable |

Everything irreplaceable converges on Proton: a scheduled `forgejo dump` (all repos) + an
rclone of `resources/`. The age key + master password live in Bitwarden + offline, never in git.

## Toolbox
- **Git + CI:** Forgejo 13 + Forgejo Actions · **Deploy/proxy:** Coolify (planned)
- **Off-site:** Proton Drive (rclone) + Bitwarden · **Host config:** chezmoi
- **Versions:** mise · **Package manager:** pnpm 10.34.4 (pinned via `packageManager`; pnpm 11.x's `onlyBuiltDependencies` is broken — avoid)
- **Secrets:** sops + age + direnv (+ gitleaks)
- **Containers:** Docker · **Notes:** Obsidian · **Docs:** Material for MkDocs (planned)
- **Web:** Astro 6 · **CMS:** Directus (planned) · **API:** .NET 10 (planned)
- **Testing:** Playwright + a unit runner (planned)
- **Observability (planned, deferred):** Grafana · Prometheus · Loki · Uptime Kuma · GlitchTip · Umami

---

## Current state (build log)

### 2026-06-28 — structure reconcile
- **`~/dev` is now a thin meta-repo** (`dev` on Forgejo) tracking root docs (`CLAUDE.md`, this README) + small non-repo text; sub-repos and heavy/binary gitignored.
- **`ops/` regrouped**: services under `ops/docker/<svc>/` (forgejo, caddy, + planned stubs); automation under `ops/scripts/` (`backup.sh`, `backup-resources.sh`, `systemd/` units). Backup re-pointed and **re-verified** (dump created + decrypted); backup-timer units now live in-repo and are installed by `bootstrap.sh` → fresh-machine reproducible.
- **`notes/`** taxonomy added: `manuals/ cheatsheets/ instructions/ logs/` (+ seeds). **`tools/`**: bruno + sqlite. **`resources/`**: assets-by-type + `<project>/{documents,specs,plans}` SDD scaffold (text git-backed; heavy assets rsync → Proton).
- **`silver-remaster`** given a Forgejo remote (regenerable game assets gitignored); **`jonnxor.is`** `docs/` scaffold added.
- Cross-platform: **WSL `~/dev` is canonical**; Windows native layer (notes/tools/resources) deferred. .NET dev stays in WSL, so `code/` is WSL-only.

**✅ Done**
- `~/dev` structure reconciled (lowercase, final buckets).
- **Forgejo 13.0.5** running in `ops/forgejo` (SQLite, http://localhost:3000).
- **Off-site backup live** 🔒: `forgejo dump` → age-encrypt → Proton Drive (the desktop app's sync folder) → daily systemd user timer. Encrypted client-side, so Proton holds only ciphertext.
- **Secrets baseline**: age key generated, `config` repo + chezmoi source, global gitignore,
  sops+age+direnv proven with a round-trip. gitleaks installed.
- **jonnxor.is**: Astro 6; **all 11 pages ported** onto a shared `Base.astro` layout (chrome via `site.js`, page scripts ordered after it via an `end` slot); builds clean + serves on `astro dev` (:4321); `.sops.yaml` + `.envrc` wired.
- **Deploy pipeline LIVE + proven** 🚀: `git push` → Forgejo → push-mirror → GitHub → **Vercel**, on two tracks:
  - `main` → **https://jonnxor.is** — production, public (`www` → 308 → apex)
  - `preview` → **https://preview.jonnxor.is** — staging (Vercel preview deployment; Deployment Protection off = public)
  - Vercel project needs env `ENABLE_EXPERIMENTAL_COREPACK=1` so it uses pinned **pnpm 10**; old `jonnxor` Vercel project retired.

**🟡 Ready / one step from done**
- Forgejo: ✅ admin (`jonnxor`) + **jonnxor.is pushed** (`origin` = Forgejo; GitHub kept as `github`) + **CI runner live** (act_runner in `ops/forgejo`; `pnpm install` + `astro build` passes on every push).
- Shell layer: add `. "$HOME/.config/dev/shell-init.sh"` to `~/.bashrc` to turn on mise+direnv auto-load.
- gitleaks pre-commit hook (left un-wired so it can't surprise-block commits).

**🔴 Pending (needs sudo, or a later phase)**
- **Caddy** (`ops/caddy`, :8080) = local prod-preview. **Coolify** deferred until `ops/` lands on an always-on host — then it (or Caddy) becomes the self-hosted proxy and the Vercel dependency can be dropped.
- Self-host **Vaultwarden** (your Bitwarden vault, on your own infra) in `ops/`, data dir → Proton — promote when `ops/` lands on an always-on host (a password manager must be reachable from every device, incl. phone).
- jonnxor.is deeper **Astro-native** backlog: blog + grimoire as content collections, nav/footer as components, **i18n** (is/en/ja), self-hosted fonts.
- **Directus** + **.NET 10 API** (project backend services).- Observability stack (after something's deployed).
