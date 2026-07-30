# Curated Brewfile migrated from nix-darwin / nix-homebrew.
# Intentionally no cleanup: never remove undeclared packages.

# homebrew/core and homebrew/cask are built into modern Homebrew; do not tap them.
# No package below needs a third-party tap. Keeping unused taps would require
# granting whole-tap trust to code that this configuration does not install.

# Core runtimes / managers
brew "chezmoi"
brew "mise"
brew "uv"
brew "direnv"
brew "pipx"
brew "python@3.14"
# nvm owns Node (see scripts/ensure-node-nvm.sh); mise declares no node runtime.
brew "nvm"
brew "pnpm"

# AI coding agents
# pi and grok have no Homebrew formula; they install from npm (npm-globals.txt).
cask "codex"
cask "claude-code"

# Shell / editor / git
brew "zsh"
brew "zsh-autosuggestions"
brew "zsh-fast-syntax-highlighting"
brew "tmux"
brew "neovim"
brew "git"
brew "gh"
brew "git-delta"
brew "ripgrep"
brew "fd"
brew "bat"
brew "fzf"
brew "eza"
brew "tree"
brew "jq"
brew "httpie"
brew "htop"
brew "glances"
brew "shellcheck"
brew "yamllint"
brew "ruff"
brew "trash-cli"
brew "coreutils"
brew "mas"
brew "wget"
brew "curl"

# Dev tooling
brew "dagger"
brew "git-lfs"
brew "automake"
brew "libtool"
brew "cargo-audit"
brew "cargo-deny"
brew "cargo-edit"
brew "cargo-nextest"
brew "cargo-binstall"
brew "sqlfluff"
brew "huggingface-cli"
brew "cmake"
brew "ninja"
brew "pkg-config"
brew "pandoc"
brew "graphviz"
brew "plantuml"
brew "imagemagick"
brew "ffmpeg"
brew "lame"
brew "chromaprint"
brew "taglib"
brew "cocoapods"
brew "xcodegen"
brew "npm-check-updates"
brew "podman"
brew "podman-compose"
brew "qemu"
brew "diffoscope"
brew "gitleaks"
brew "semgrep"
brew "tokei"
brew "typos-cli"
brew "sccache"
brew "gnupg"
brew "age"
brew "sops"
brew "nmap"
cask "mitmproxy"
brew "apktool"
brew "bento4"
brew "witr"

# Optional security audit
brew "lynis"

# Casks
cask "macfuse"
cask "zoom"
cask "appcleaner"

# Objective-See security monitors
cask "blockblock"
cask "knockknock"
cask "oversight"

cask "basictex"
cask "gimp"
cask "iterm2"
cask "logi-options+"
cask "thunderbird"
cask "calibre"
cask "orcaslicer"
cask "ollama-app"
cask "phoenix"
cask "sdformatter"
cask "steam"
cask "the-unarchiver"
cask "telegram"
cask "inkscape"
cask "dbeaver-community"
cask "podman-desktop"
cask "hex-fiend"

# Productivity
cask "obsidian"
# These apps predated Homebrew management. Force permits the one-time adoption
# by replacing a different installed version; subsequent bundle runs see the
# cask receipt and do not reinstall it.
cask "libreoffice", args: { force: true }
cask "onedrive"

# Communication / remote access
cask "discord"
cask "whatsapp"
cask "teamviewer"
cask "nordvpn"

# Peripherals
# Embrava Connect (busylight, used by the Phoenix config) has no cask;
# install it manually from embrava.com.
cask "elgato-stream-deck"
cask "elgato-control-center"
cask "camo-studio"

# 3D printing
cask "bambu-studio", args: { force: true }

# Fonts
cask "font-chivo-mono"
cask "font-jetbrains-mono-nerd-font"
cask "font-monaspace"
cask "font-noto-color-emoji"
