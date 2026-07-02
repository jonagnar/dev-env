# dev — meta-repo dev-environment

A tiny, secret-free meta-repo that provisions a machine, manages sops+age secrets
via mise, and produces encrypted backups. Clone it, run one script. Runs anywhere
bash does: **WSL/Linux**, or **native Windows via Git Bash** (ships with Git —
mise is bootstrapped through winget there).

## Quick start
1. `git clone <repo> dev && cd dev`  *(on Windows: in a Git Bash shell)*
2. Preview: `./install.sh --dry-run`  → then `./install.sh`
3. Open a new shell — mise + secrets auto-load.

## Layout — every file, and what it does

```
dev/                                ← the meta-repo: clone it, run install.sh
│
├─ install.sh                       provision/refresh this machine (idempotent, 5 phases)
├─ backup.sh                        encrypted snapshot of every repo (manual, never prompts)
├─ restore.sh                       decrypt a snapshot + stage its bundles for cloning
│
├─ src/                             YOUR repos live here, flat — contents gitignored,
│  └─ <project>/                    each one its own clone (this is what gets backed up)
│
├─ .config/                         machinery the scripts drive
│  ├─ mise/core.toml                core toolchain: sops · age · chezmoi · gitleaks
│  ├─ sops/.sops.yaml.tmpl          seed for this machine's age recipient
│  │                                (rendered ONCE by install — added recipients survive)
│  └─ chezmoi/                      host-config templates → applied to $HOME
│     ├─ .chezmoi.toml.tmpl         chezmoi config: records the source dir
│     └─ dot_config/
│        ├─ dev/shell-init.sh.tmpl  → ~/.config/dev/shell-init.sh (env vars + mise activation)
│        ├─ dev/gitconfig.tmpl      → ~/.config/dev/gitconfig (aliases, hooks wiring)
│        └─ git/
│           ├─ ignore               → global gitignore: plaintext secrets can't be staged, ever
│           └─ template/hooks/…pre-commit  → gitleaks guard, lands in every new/cloned repo
│
├─ README.md · AGENTS.md · CLAUDE.md    this file · instructions for AI agents · pointer
├─ .gitignore · .gitattributes          src/* & restore-*/ ignored · LF endings enforced
└─ LICENSE                              MIT
```

All three scripts support `--help` and `--dry-run`; `restore` prompts unless `--yes`.

`install.sh` never rewrites your dotfiles — it *appends one line each*:

```
$HOME/
├─ .bashrc                       + one line: source ~/.config/dev/shell-init.sh
├─ .gitconfig                    + one line: [include] ~/.config/dev/gitconfig
└─ .config/
   ├─ dev/shell-init.sh          DEV_ROOT · sops key path · mise activation
   ├─ dev/gitconfig              shared git config (yours wins if set after the include)
   ├─ dev/backup-dir             your answer to "where should backups go?" (asked once)
   └─ sops/age/keys.txt          🔑 THE key (0600) — everything decrypts with this one file.
                                    Back it up in your password manager. It exists nowhere else.
```

## Secrets (mise + sops + age) — the actual workflow

One **age key** decrypts everything. Secrets live *encrypted* in each repo;
**mise decrypts them natively, in memory, on `cd`** — nothing hits disk. Plaintext
`.env` is blocked from every repo by the global gitignore, and the gitleaks
pre-commit hook guards whatever slips past.

A project wired for multi-tenant secrets looks like this:

```
src/demo-api/
├─ .sops.yaml                    recipients: you · teammate · CI   (public keys — commit it)
├─ .env.example                  variable NAMES only (plaintext, safe, committed)
├─ mise.toml                     [env] _.file = "secrets/shared.env.json"
├─ mise.acme.toml                [env] _.file = "secrets/acme.env.json"   (MISE_ENV=acme)
├─ mise.globex.toml              [env] _.file = "secrets/globex.env.json" (MISE_ENV=globex)
└─ secrets/
   ├─ shared.env.json            🔒 ciphertext — safe to commit & push
   ├─ acme.env.json              🔒 per-tenant
   └─ globex.env.json            🔒 per-tenant

$ cd src/demo-api                → mise decrypts shared.env.json → vars in your shell
$ MISE_ENV=acme  <same cd>       → + acme.env.json on top — different tenant, zero code change
```

**Per project, once** — recipient file + mise wiring:
```sh
cd src/<project>
cp "$DEV_ROOT/.config/sops/.sops.yaml" .sops.yaml   # public keys only — commit it
mise trust                                          # mise won't load an untrusted config
```
Name secrets `<name>.env.json` (or `.yaml`/`.toml`) — mise's sops support reads
those formats, and bare `.env.*` stays gitignored as a plaintext footgun-guard.

**Create / edit a secret** (opens `$EDITOR`, encrypts on save):
```sh
sops secrets/shared.env.json
```

**Teammates / CI**: append their age *public* key to the project's `.sops.yaml`
(comma-separated), then re-encrypt: `sops updatekeys secrets/*.env.json`.
Off-boarding = remove the key + `updatekeys` again. The ciphertext is the only copy;
each reader decrypts with their own private key — no shared secret to pass around.

**Caveats**
- The gitleaks hook lands via git's `templateDir`, so it applies to repos
  **created/cloned after** install. Retrofit an existing clone with:
  `cp ~/.config/git/template/hooks/pre-commit .git/hooks/`
- Compose stacks that need a literal env *file* keep the dotenv style:
  `*.env.sops` in git, decrypted with the sops CLI on the host. mise-native is
  for your interactive/dev shell env.
- On Windows, `chmod 600` on the key is cosmetic — the real protection is your
  NTFS profile ACL (age prints a warning; it's expected).

## Backups — what one run of ./backup.sh does

```
  dev  (meta-repo) ─┐
  src/infra        ─┤   git bundle --all       tar            age -r <your pubkey>
  src/notes        ─┼──►  one .bundle each ──►  one .tar  ──►  🔒 dev-backup-<ts>.tar.age
  src/<each repo>  ─┘         (tmp)              (tmp)               │
                                                                     ▼
                                                                DESTINATION
```

**IN** — the meta-repo + every git repo directly under `src/`: full history, all
branches, exactly as `git clone` would recover them.

**OUT** — everything untracked or gitignored (live Docker volumes, `node_modules`,
plaintext `.env`), anything outside `dev/`, and the age key itself — restore
deliberately needs the key from your password manager, not from the backup.

The plaintext stages only in `$TMPDIR` and is shredded even on failure — the
destination only ever sees ciphertext, so it's safe to point at a folder your
sync app uploads.

**Destination** (first match wins) — `restore` looks in the same place:
1. `--backup-dir DIR` (per run)
2. `$DEV_BACKUP_DIR` (env)
3. `~/.config/dev/backup-dir` — **install asks once** and saves your answer
4. `~/backups`

**Off-site tip**: sync apps (Proton Drive, OneDrive, …) can only watch *local*
folders — a WSL path is a network drive to Windows and can't be synced. So flip
the direction: answer install's question with a folder *inside* the app's synced
tree (e.g. `/mnt/c/Proton Drive/My files/backups/dev-snapshots`).

> Live service state (databases, container volumes) is **not** in these bundles —
> dump it with the service's own tooling (e.g. a nightly `forgejo dump` if you
> self-host git). Rule of thumb: git bundles cover code + config; service dumps
> cover live data.

## Disaster recovery
1. Install git + age; clone this repo.
2. Restore your age **private** key from your password manager to
   `~/.config/sops/age/keys.txt`.
3. Fetch the newest `dev-backup-*.tar.age` from your sync provider onto disk —
   a fresh machine has no saved destination yet.
4. `./restore.sh --archive <path/to/that.tar.age>` (or, before scripts exist:
   `age -d -i ~/.config/sops/age/keys.txt <archive>.tar.age | tar -x`).
5. `git clone` each `*.bundle` from the staging dir to rebuild repos.
6. `./install.sh` to finish provisioning.
