# dev — meta-repo dev-environment

A tiny, secret-free meta-repo that provisions a machine, manages sops+age secrets
via mise, and produces encrypted backups. Clone it, run one script. Runs in
WSL/Linux (bash).

## Quick start
1. `git clone <repo> dev && cd dev`
2. Preview: `./scripts/init.sh --dry-run`  → then `./scripts/init.sh`
3. Open a new shell — mise + secrets auto-load.

## Actions
| Verb | Purpose |
|------|---------|
| `scripts/init.sh` | provision/refresh this machine |
| `scripts/verify.sh` | read-only health check |
| `scripts/update.sh` | pull + update tools + re-apply chezmoi |
| `scripts/backup.sh` | age-encrypted snapshot → `backups/` (also daily) |
| `scripts/restore.sh` | decrypt + staged restore |

All support `--help` and `--dry-run`; `restore`/`update` prompt unless `--yes`.

## Backups
`backup` writes `backups/dev-backup-<timestamp>.tar.age` — git bundles of the
meta-repo + each `ops/<repo>` (including `ops/infra`), age-encrypted to your public
key. **You** choose where to sync `backups/` — point Proton/Drive/Syncthing at it;
encrypted at rest, the provider only ever sees ciphertext.

> Live service state (the Forgejo DB, container volumes) is **not** in these bundles.
> It's dumped separately by `ops/infra` (see `ops/infra/RESTORE.md`). Rule of thumb:
> git bundles cover code + config; the Forgejo dump covers live data.

## Disaster recovery
1. Install git + age; clone this repo.
2. Restore your age **private** key from Vaultwarden/Bitwarden to
   `~/.config/sops/age/keys.txt`.
3. `./scripts/restore.sh` (or, before scripts exist:
   `age -d -i ~/.config/sops/age/keys.txt backups/<archive>.tar.age | tar -x`).
4. `git clone` each `*.bundle` from the staging dir to rebuild repos.
5. `./scripts/init.sh` to finish provisioning.
