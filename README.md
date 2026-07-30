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
3. User setup (mise tools, TPM plus its plugins, Lynis profile restore)
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

Language runtimes: **mise** + **uv** + **direnv**. Helpers: `penv311`, `penv313`, `penv314`.

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

After postflight is green and tools no longer resolve under `/nix`:

```bash
~/.config/chezmoi/scripts/remove-nix.sh
```

Requires typing `REMOVE-NIX`. Does **not** delete `~/.config/nix`. Shell files
under `/etc` are restored from the installer's `.backup-before-nix*` copies
rather than being deleted outright.

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
