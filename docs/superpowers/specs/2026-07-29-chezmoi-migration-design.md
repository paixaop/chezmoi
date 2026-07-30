# Nix to chezmoi Migration Design

## Goal

Replace the current nix-darwin, home-manager, nix-homebrew, and Nix dev-shell setup with a curated macOS configuration based on chezmoi, Homebrew, and idempotent shell scripts. The new source lives at `~/.config/chezmoi`. The existing `~/.config/nix` repository remains unchanged for rollback.

Success means a fresh Apple Silicon Mac can be bootstrapped from one script, can safely reapply the configuration, and no daily shell or development workflow depends on `/nix`.

## Decisions

- Use `~/.config/chezmoi` as both the Git checkout and explicit chezmoi source directory.
- Use a modular chezmoi-native layout rather than one monolithic installer.
- Collect generic user and machine values interactively instead of encoding the existing hostnames.
- Use Homebrew as the system package manager.
- Use mise for language runtimes, uv for Python projects and tools, and direnv for project activation.
- Prompt for sudo during `chezmoi apply` and apply privileged settings last.
- Preserve the existing application firewall policy, including block-all-incoming mode.
- Keep Nix removal in a separate, manually invoked script.
- Do not remove, archive, or modify `~/.config/nix`.

## Source Layout

```text
~/.config/chezmoi/
├── .chezmoi.toml.tmpl
├── .chezmoiignore
├── Brewfile
├── bootstrap.sh
├── README.md
├── docs/
├── scripts/
│   └── remove-nix.sh
├── dot_config/
│   ├── direnv/
│   ├── mise/
│   ├── nvim/
│   └── ...
├── dot_local/bin/
├── dot_zshrc.tmpl
├── dot_gitconfig.tmpl
├── dot_tmux.conf
├── run_onchange_before_10-homebrew.sh.tmpl
├── run_onchange_after_20-user-setup.sh.tmpl
├── run_onchange_after_30-macos-defaults.sh.tmpl
├── run_onchange_after_40-dock.sh.tmpl
├── run_onchange_after_50-system-settings.sh.tmpl
└── run_after_90-postflight.sh.tmpl
```

Files such as `Brewfile`, documentation, bootstrap helpers, and the manual Nix removal script remain source-only through `.chezmoiignore`. Chezmoi scripts are ordered by filename and rerun only when their rendered content changes, except postflight verification, which runs after every apply.

Because the requested source path is also chezmoi's default configuration directory, the generated `chezmoi.toml` is ignored by both Git and chezmoi. `.chezmoi.toml.tmpl` remains the tracked initialization template, while the rendered configuration stays machine-local and is never interpreted as a file to deploy into `$HOME`.

## Bootstrap and Apply Flow

`bootstrap.sh` supports two modes:

1. From an existing checkout, it treats its own directory as the source.
2. When downloaded independently, it requires a repository URL through `CHEZMOI_REPO`, clones to `~/.config/chezmoi`, and continues from there.

It verifies macOS on Apple Silicon, installs Homebrew and chezmoi when absent, initializes the interactive chezmoi data, displays the pending diff, and applies the source explicitly with `--source "$HOME/.config/chezmoi"`.

The interactive template records name, primary email, optional work and personal Git identities, hostname, timezone, and optional application groups. Non-secret answers live in the normal chezmoi configuration. No credentials or tokens are stored in the source.

Apply order is:

1. Install or update Homebrew dependencies with `brew bundle`.
2. Render user dotfiles and helper commands.
3. Configure mise, uv, direnv, TPM, LazyVim, and Phoenix configuration.
4. Apply user-level macOS defaults.
5. Configure the Dock from applications that actually exist.
6. Request sudo once and apply system settings.
7. Run postflight verification and print a summary.

## Packages and Applications

The Brewfile preserves actively used command-line tools, security tools, GUI applications, and fonts from the current configuration. It installs without cleanup so undeclared local software is never removed.

The migration removes:

- Nix daemon, flake, garbage-collection, substitute-checking, and rebuild tooling
- Nix-only package overlays and store paths
- duplicate runtime packages replaced by mise
- build libraries that have no identified non-Nix consumer
- the `/Applications/Nix Apps` alias mechanism
- Nix certificate and compiler environment overrides
- Nix-specific dev-shell and `use flake` aliases

GUI applications currently delivered by Nix move to Homebrew casks when a maintained cask exists. Applications with no suitable cask remain documented manual installs. Dock configuration skips missing applications rather than creating broken entries.

## Development Environment

mise manages Python, Node.js, Go, and Rust versions. uv manages Python virtual environments and Python command-line tools. direnv loads per-project environment files without hardcoded global `VIRTUAL_ENV` values.

Portable shell helpers replace the current Python dev-shell aliases. Native build variables are configured per project only when required; global Nix store library and header paths are not translated.

## Managed Dotfiles

Chezmoi directly manages:

- zsh startup, aliases, completions, and plugins using Homebrew paths only
- Git identity, conditional includes, ignore rules, and the `gh` credential helper resolved from `PATH`
- tmux configuration and helper scripts, with TPM replacing nixpkgs plugins
- Neovim and LazyVim configuration, while leaving plugin data runtime-managed
- Cargo configuration without Nix linker paths
- markdownlint configuration
- mise and direnv configuration
- useful maintenance scripts that have no Nix dependency

Phoenix remains installed through Homebrew. Its currently pinned configuration is fetched reproducibly during apply rather than copied from a mutable branch.

## macOS User Settings

The defaults script translates the active Finder, Dock, global UI, screenshot, screensaver, trackpad, login-window, and Software Update preferences. It uses `defaults` only for domains where that tool is appropriate and restarts affected user processes after successful changes.

Dock entries are generated from the curated desired list and only retained when their application paths exist.

## Privileged System Settings

The final system script obtains and refreshes sudo authorization, compares current state before changing it, and logs every action. It:

- sets ComputerName, HostName, and LocalHostName with `scutil`
- sets the configured timezone with `systemsetup`
- enables the application firewall, stealth mode, signed built-in applications, signed downloaded applications, and block-all-incoming mode
- configures Touch ID for sudo in `/etc/pam.d/sudo_local`, preserving a timestamped backup before the first change
- enables biometric system unlock with `bioutil` when supported

No `networksetup` or `pmset` policy is introduced because the existing configuration contains no explicit desired network or power values. Those tools are added only if a concrete policy is later specified.

Apply output and documentation warn that block-all-incoming mode can prevent local servers, sharing, and inbound development traffic.

## Error Handling and Idempotency

Scripts use strict shell settings, validate required commands, compare current and desired state, and stop on errors. A failed stage prevents dependent later stages but does not remove existing dotfiles, packages, or the Nix installation.

Homebrew uses `brew bundle` without cleanup. macOS settings are rewritten only when values differ. Privileged file edits use temporary files, validation, and atomic replacement. Unsupported hardware-specific operations are reported as skipped rather than treated as failures.

## Verification

Development-time verification includes:

- shell parser checks, ShellCheck, and formatting checks for all scripts
- chezmoi source-state validation, `chezmoi diff`, and dry-run inspection
- Brewfile validation and `brew bundle check`
- template execution with representative generic profile data

Postflight verification checks:

- expected commands are present and do not resolve under `/nix`
- mise, uv, direnv, tmux, Neovim, and Git configuration are usable
- important `defaults` values match the desired state
- `scutil` names and `systemsetup` timezone match profile data
- firewall and block-all-incoming settings are active
- the Touch ID PAM include is valid

The summary separates passed, skipped, warning, and failed checks.

## Nix Removal

`scripts/remove-nix.sh` is never run by chezmoi. It first runs postflight checks and refuses to continue if replacement commands still resolve under `/nix` or required setup checks fail. It lists destructive actions and requires explicit typed confirmation before unloading Nix services or deleting Nix-managed files.

The removal script does not touch `~/.config/nix`, preserving the configuration history as a rollback reference.

## Documentation

The README documents:

- initial bootstrap and required `CHEZMOI_REPO` behavior
- regular `chezmoi diff` and apply workflows using the explicit source path
- adding and updating packages
- changing interactive profile data
- troubleshooting Homebrew, templates, sudo, firewall, and macOS defaults
- validating the replacement before manually removing Nix
- the consequences of block-all-incoming firewall mode
