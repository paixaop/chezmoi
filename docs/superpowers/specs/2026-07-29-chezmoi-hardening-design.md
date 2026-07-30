# Chezmoi hardening design

## Goal

Make the macOS configuration safe to apply repeatedly, reproducible enough to bootstrap a new machine, and testable before changes reach a workstation.

The repository remains macOS and Apple Silicon specific. Cross-platform support is outside this change.

## Policy and machine data

`.chezmoi.toml.tmpl` will continue to collect the user's name, primary email, optional work email, personal email, hostname, and timezone. User-specific email defaults and hardcoded identity addresses will be removed.

Machine policy will include:

- application firewall enabled;
- stealth mode enabled;
- block-all incoming traffic disabled by default.

The system settings script will render these values and enforce them idempotently. The README will explain how to regenerate machine-local data after the template changes.

## Safe repeated application

### Postflight

Postflight will distinguish required bootstrap failures from configuration drift:

- missing required commands or commands resolving through Nix are fatal;
- Dock, timezone, firewall policy, and Touch ID drift are warnings;
- the final exit status is nonzero only for fatal checks.

This keeps verification useful without reporting an otherwise successful `chezmoi apply` as failed.

### Dock

The managed application list will be merged into the current `persistent-apps` list:

- existing applications and folder stacks remain in their current order;
- a managed application is appended only when it exists and is not already present;
- duplicate file URLs are not introduced;
- Dock restarts only when the plist changes.

Chezmoi will not claim exclusive ownership of the Dock.

### macOS defaults

All defaults will use compare-before-write behavior. The script will track which process domains changed and restart only the affected processes:

- Dock for Dock defaults;
- Finder for Finder defaults;
- SystemUIServer for global, screenshot, screensaver, or trackpad defaults when required.

## Identity and shell configuration

Git identity templates will use prompted values:

- personal directories use `personalEmail`;
- the work directory include is emitted only when `workEmail` is non-empty;
- the primary identity continues to use `email`.

The unsafe `claudex` alias will be removed. Stale NVM and ESP-IDF settings will be removed because mise owns language runtimes and ESP-IDF is not installed by this repository.

Login environment setup, including Homebrew initialization and base path construction, will move to `.zprofile`. Interactive aliases, completion, prompt, plugins, mise activation, and direnv hooks remain in `.zshrc`.

Only `~/.local/bin` will contain the managed tmux layout helpers. Tmux configuration and aliases will use that path.

## Dependency management

Dagger will be installed through Homebrew rather than a remote shell installer. Shell autosuggestions and syntax highlighting will use Homebrew-managed packages instead of moving zinit branches. Zinit will be removed if it has no remaining consumers.

TPM will remain a Git checkout, but user setup will run its plugin installer after cloning or updating it. Failures remain warnings so a transient GitHub outage does not invalidate the rest of apply.

Homebrew locking will be enabled by removing `--no-lock`. The generated lockfile will be managed if the installed Homebrew Bundle version produces one. Package updates remain an explicit maintenance operation.

## Verification

`scripts/verify.sh` will provide one local entry point that:

1. checks required verification commands;
2. renders chezmoi templates using the current machine data;
3. runs ShellCheck on source shell scripts and rendered shell templates;
4. validates formatting or syntax for JSON, TOML, Python snippets, and shell where applicable;
5. runs `chezmoi verify` and a non-mutating diff;
6. runs `brew bundle check` when Homebrew is available.

A GitHub Actions workflow will run the portable subset on a macOS runner. Checks requiring private machine data or privileged mutation will be skipped or supplied deterministic test data.

## Migration and documentation

The unfinished shell-backup restoration path in `scripts/remove-nix.sh` will restore known pre-Nix backups when present and avoid replacing valid regular files. Existing backup and test scripts will be preserved.

The README will gain:

- the concrete repository URL `https://github.com/paixaop/chezmoi.git`;
- GitHub user `paixaop` in bootstrap examples;
- machine-policy regeneration instructions;
- troubleshooting for Homebrew, templates, sudo, firewall, and defaults;
- a secrets section describing chezmoi encryption with age or SOPS without adding real secrets;
- the local verification command.

The local Git remote `origin` will be configured to `https://github.com/paixaop/chezmoi.git`. No commit or push is part of this implementation.

## Error handling

Mutating scripts retain `set -euo pipefail`. Optional integrations use warnings only when failure does not leave the core configuration inconsistent. Privileged writes remain compare-before-write where their tools expose readable state.

Remote installation scripts will not be executed. Network-backed package and plugin operations will report enough context to retry.

## Testing

Verification will include:

- ShellCheck for changed shell sources and rendered templates;
- tests for Dock merge behavior using temporary plist fixtures;
- tests for postflight fatal-versus-warning accounting without changing host settings;
- existing Nix backup tests;
- `chezmoi execute-template`, `chezmoi verify`, and `chezmoi diff`;
- a review of the final Git diff to ensure unrelated staged work is preserved.

Host-mutating scripts will not be executed during automated verification.

## Out of scope

- Linux or Intel Mac support;
- adding or importing actual credentials, SSH keys, or encrypted secret payloads;
- publishing the repository;
- creating the initial commit;
- force-changing a pre-existing Git remote with a different URL without reporting the conflict.
