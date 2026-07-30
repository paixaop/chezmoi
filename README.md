# Chezmoi macOS configuration

Replaces nix-darwin / home-manager / nix-homebrew with chezmoi, Homebrew, and shell scripts.

Source directory: `~/.config/chezmoi` (also the Git checkout).

The previous Nix config at `~/.config/nix` is left untouched for rollback.

Repository: <https://github.com/paixaop/chezmoi>

## Bootstrap (fresh machine)

```bash
# Option A: already cloned to ~/.config/chezmoi
~/.config/chezmoi/bootstrap.sh

# Option B: download bootstrap and clone from the remote
CHEZMOI_REPO=https://github.com/paixaop/chezmoi.git \
  bash -c "$(curl -fsSL https://raw.githubusercontent.com/paixaop/chezmoi/main/bootstrap.sh)"
```

Bootstrap installs Homebrew and chezmoi if needed, prompts once for name/emails/hostname/timezone, shows a diff, then applies.

## Day-to-day

```bash
export CHEZMOI_SOURCE="$HOME/.config/chezmoi"
chezmoi --source="$CHEZMOI_SOURCE" diff
chezmoi --source="$CHEZMOI_SOURCE" apply
```

Aliases after zsh reload: `chezmoi-diff`, `chezmoi-apply`, `chezmoi-cd`, `chezmoi-verify`.

## What apply does

1. `brew bundle install` from `Brewfile` (no cleanup, no uninstall of undeclared packages, no implicit upgrades)
2. Deploy dotfiles (zsh, git, tmux, nvim, mise, direnv, cargo, helpers)
3. User setup (mise tools, home direnv Python 3.14 env if missing, Node via nvm, global npm packages, cargo packages, TPM plus its plugins, Lynis profile restore)
4. macOS `defaults` (compare-before-write; only restarts Dock/Finder/SystemUIServer when something changed)
5. Dock: adds managed apps that are installed, keeping existing tiles and order
6. Privileged settings (`scutil`, `systemsetup`, firewall policy, Touch ID sudo / unlock) — prompts for sudo
7. Postflight checks

Re-applying without source changes is a no-op: nothing is rewritten and no processes are restarted.

## Verify before applying

```bash
~/.config/chezmoi/scripts/verify.sh
```

Renders every template into a temporary directory, runs ShellCheck over both the
sources and the rendered scripts, checks Python and TOML syntax, runs the unit
tests, and reports `chezmoi diff` plus missing Brewfile dependencies. It never
applies anything. The same script runs in CI on a macOS runner.

## Machine policy

Security policy lives in the machine-local `chezmoi.toml`, not in Git:

```toml
[data.policy]
    firewallEnabled = true
    firewallStealthMode = true
    firewallBlockAll = false
```

`firewallBlockAll` rejects all inbound connections, which breaks local dev
servers, AirDrop, and screen sharing. It defaults to off. Enable it per machine:

```bash
$EDITOR ~/.config/chezmoi/chezmoi.toml     # set firewallBlockAll = true
chezmoi --source="$HOME/.config/chezmoi" apply
```

Firewall settings are compare-before-write, so applying repeatedly never toggles state.

## Packages

Edit `Brewfile`, then re-apply (or change the homebrew run script so its content hash changes).

Homebrew Bundle no longer supports lockfiles, and the install step uses
`--no-upgrade` so an apply never silently upgrades unrelated packages. Upgrade
explicitly when you want to:

```bash
brew update && brew upgrade
```

Language runtimes: **mise** (Python, Go, Rust) + **uv** + **direnv**, and **nvm** for Node.
Helpers: `penv311`, `penv313`, `penv314`.

On apply, if `~/.direnv/python3.14` is missing, user-setup creates a home
direnv environment (`use mise` + `layout python python3.14`). An existing
custom `~/.envrc` without that layout is left alone.

### Node

nvm owns Node. mise deliberately declares no `node` runtime and the Brewfile
installs no system `node`, so there is exactly one Node manager.

`scripts/ensure-node-nvm.sh` installs the latest Node and sets it as the nvm
default. nvm refuses to run when npm declares a global `prefix`, so that
setting is removed from `~/.npmrc` (with a timestamped backup) and global
packages live under the active Node version instead of `~/.npm-global`.

### Declarative package lists

Three plain-text lists drive the non-Homebrew installs. Editing any of them
changes the user-setup script hash, so the next apply picks them up:

| File | Installs | Notes |
|------|----------|-------|
| `npm-globals.txt` | global npm packages | includes pi, grok CLI, pi extensions, language servers |
| `cargo-packages.txt` | cargo binaries | uses `cargo-binstall` when available |
| `Brewfile` | formulae and casks | everything with a Homebrew package |

Each installer only adds what is missing and never removes undeclared
packages.

### AI coding agents

| Agent | Source |
|-------|--------|
| Claude Code | Homebrew `claude-code` |
| OpenAI Codex CLI | Homebrew `codex` |
| Codex desktop app | Homebrew cask `codex` |
| pi coding agent | npm `@earendil-works/pi-coding-agent` |
| grok CLI | npm `@vibe-kit/grok-cli` |

If you previously used Anthropic's native Claude Code installer, the Homebrew
copy takes over; remove `~/.local/share/claude` once you have confirmed the
managed one works.

## Git identities

`~/.gitconfig` uses the prompted primary email. Directory-scoped identities:

- `~/code/` and `~/.config/` use `personalEmail`
- `~/darksector/` uses `workEmail`, and the include is omitted entirely when no work email was given

## Secrets

No secrets are stored in this repository. `age`, `sops`, and `gnupg` are
installed for when they are needed. To add an encrypted file:

```bash
chezmoi --source="$HOME/.config/chezmoi" add --encrypt ~/.config/some/secret.toml
```

Configure the recipient in `chezmoi.toml` (`encryption = "age"` plus an
`[age]` section) before adding encrypted files. `chezmoi.toml` itself holds
machine-local data and is excluded from Git and from deployment.

## Shell layout

- `~/.zprofile` — environment: Homebrew, PATH, compiler and pkg-config variables
- `~/.zshrc` — interactive: prompt, completion, aliases, mise, direnv, plugins

`.zshrc` sources `.zprofile` when a non-login interactive shell skipped it.

## Back up the Nix configuration

Before applying chezmoi or removing Nix:

```bash
~/.config/chezmoi/scripts/backup-nix-config.sh
```

Backups are written to `~/nix-backups/` with a SHA-256 checksum. The archive includes `~/.config/nix`, a system manifest, and dereferenced copies of Nix-managed dotfiles. It intentionally excludes the `/nix` store.

## Remove Nix (manual)

This is a two-step process, and the order matters.

### Step 1: leave Nix territory

`nix-homebrew` owns Homebrew itself on this machine: `/opt/homebrew/bin/brew` and
the entire `/opt/homebrew/Library/Homebrew` implementation are symlinks into
`/nix/store`. The `Cellar`, `Caskroom`, and `Taps` are real directories, but
`brew` stops existing the moment the store is deleted — and it cannot reinstall
itself without a working `brew`. The same applies to `git`, `tmux`, and `nvim`,
which arrive via `/etc/profiles/per-user/$USER` (a symlink farm into the store
that looks like an ordinary path).

So the real Homebrew must be restored **while Nix is still installed**:

```bash
~/.config/chezmoi/scripts/prepare-nix-exit.sh --dry-run   # inspect the plan
~/.config/chezmoi/scripts/prepare-nix-exit.sh
```

It replaces the Nix brew launcher and `Library/Homebrew` symlink with a real
Homebrew git checkout in place (preserving every installed package), then
installs only the minimal removal toolchain: `chezmoi`, `git`, `gh`, `tmux`,
`nvim`, `mise`, `uv`, and `direnv`. The full Brewfile is intentionally deferred
so unrelated GUI apps and optional taps cannot block Nix removal. The script
ends with a table showing what still resolves under Nix; every entry must read
`ok`.

### Step 2: remove Nix

Once postflight is green and nothing resolves under `/nix`:

```bash
~/.config/chezmoi/scripts/remove-nix.sh
```

Requires typing `REMOVE-NIX`. The preflight refuses to run if Homebrew is still
Nix-managed or if any required tool is missing or store-backed, and it reports
every problem at once rather than one per run. This is a full uninstall for
Determinate Nix + nix-darwin + home-manager on this machine:

1. runs the official `/nix/nix-installer uninstall` when the receipt is present
2. unloads every `org.nixos.*` and `systems.determinate.*` LaunchDaemon
3. restores `/etc` shell files from `*.before-nix-darwin` backups and removes
   `/etc/static` plus every symlink that pointed into it
4. removes the `nix` line from `/etc/synthetic.conf` and the `/nix` APFS mount
   from `/etc/fstab`
5. unmounts and deletes the **Nix Store** APFS volume (~162 GB here)
6. deletes all `_nixbld*` users, the `nixbld` group, and the System keychain
   password used to unlock the volume
7. deletes per-user Nix state, `/Applications/Nix Apps`, and
   `~/Applications/Home Manager Apps`
8. strips `/nix/store` and `hm-session-vars` sources from `~/.bashrc`,
   `~/.profile`, and `~/.zprofile`
9. verifies each of the above is gone and exits non-zero on leftovers

`~/.config/nix` is kept by default for rollback. Pass `--also-delete-config`
to remove it. If a previous attempt left the system half-clean, re-run with
`--force-scrub`.

A reboot is recommended afterwards so the synthetic `/nix` entry clears.
Then re-apply chezmoi so `/etc/pam.d/sudo_local` (Touch ID sudo) is
recreated — nix-darwin owned that file as a symlink into `/etc/static`.

## Re-prompt profile data

```bash
rm ~/.config/chezmoi/chezmoi.toml
chezmoi --source="$HOME/.config/chezmoi" init --prompt
chezmoi --source="$HOME/.config/chezmoi" apply
```

## Troubleshooting

**`chezmoi verify` says the config template changed.** `.chezmoi.toml.tmpl` was
edited after `chezmoi.toml` was generated. Re-run `chezmoi init --prompt` as
above, or hand-edit `chezmoi.toml` to add the new keys.

**A template fails to render.** Run `scripts/verify.sh`; it renders every
template with fixture data and prints the failing file and error. A missing
`[data]` key is the usual cause.

**Homebrew stage fails.** Run `brew update` and
`brew bundle check --file=~/.config/chezmoi/Brewfile --verbose` to see which
formula or cask is unavailable. Casks needing a password will prompt.

**Sudo prompts repeatedly or times out.** The privileged stage caches sudo for
its own duration only. Run `sudo -v` immediately before `chezmoi apply`.

**Inbound connections stopped working.** Check whether block-all is on:

```bash
/usr/libexec/ApplicationFirewall/socketfilterfw --getblockall
```

Set `firewallBlockAll = false` in `chezmoi.toml` and re-apply.

**A `defaults` change did not appear.** Some preferences are cached by a running
app. Log out and back in, or quit the app before re-applying.

**A run script did not re-run.** `run_onchange_` scripts execute only when their
rendered content changes. Force one with
`chezmoi --source="$HOME/.config/chezmoi" state delete-bucket --bucket=entryState`.
