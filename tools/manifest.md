# tools/manifest.md — GUI / desktop apps (mise can't manage these)

Machine-global CLIs live in `.config/mise/core.toml` (add with `mise use -g`).
This documents per-machine tools *not* in mise core — GUI apps, optional CLIs,
and local tools. Binaries in `tools/bin/` aren't committed (re-downloadable);
this manifest is. (Tool *source* lives with the repo that uses it — e.g. `md2pdf`
now in `ops/resources/_tools/`.)

| Tool | What / install |
|------|----------------|
| Bruno (API client) | GUI, Git-friendly API client. `scoop install bruno` (or winget). See `tools/bruno/`. |
| SQLite (`sqlite3`) | CLI + embedded DB for local data/inspection. `scoop install sqlite`. See `tools/sqlite/`. |
| tea (Forgejo CLI) | Forgejo/Gitea CLI (PRs/issues/repos). Binary lives at `tools/bin/tea` (re-download from Gitea `tea` releases). See `tools/tea/`. |
