#!/usr/bin/env bash
# Script to restore custom Lynis profile after Homebrew updates
# This ensures the custom.prf file persists across lynis updates

set -euo pipefail

LYNIS_DIR="/opt/homebrew/Cellar/lynis"
CUSTOM_PROFILE_BACKUP="$HOME/.lynis-custom.prf"

# Highest version directory in the Cellar, or empty when there is none.
latest_cellar_version() {
    find "$LYNIS_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null \
        | while IFS= read -r dir; do basename "$dir"; done \
        | sort -V \
        | tail -1
}

# Check if lynis is installed
if ! command -v lynis &> /dev/null; then
    echo "Error: lynis is not installed"
    exit 1
fi

# Get current lynis version - try multiple methods
LYNIS_VERSION=$(lynis --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)

# If version detection failed, try to find the latest version directory
if [ -z "$LYNIS_VERSION" ] && [ -d "$LYNIS_DIR" ]; then
    LYNIS_VERSION=$(latest_cellar_version)
fi

# Final check
if [ -z "$LYNIS_VERSION" ] || [ ! -d "${LYNIS_DIR}/${LYNIS_VERSION}" ]; then
    echo "Warning: Could not determine lynis version, trying to find it..."
    if [ -d "$LYNIS_DIR" ]; then
        LYNIS_VERSION=$(latest_cellar_version)
    fi
    if [ -z "$LYNIS_VERSION" ]; then
        echo "Error: Could not find lynis installation directory"
        exit 1
    fi
fi

CUSTOM_PROFILE_TARGET="${LYNIS_DIR}/${LYNIS_VERSION}/custom.prf"

# Check if backup exists
if [ ! -f "$CUSTOM_PROFILE_BACKUP" ]; then
    echo "Warning: Backup file not found at $CUSTOM_PROFILE_BACKUP"
    echo "Creating backup from current custom.prf if it exists..."
    
    # Try to find existing custom.prf
    if [ -f "$CUSTOM_PROFILE_TARGET" ]; then
        cp "$CUSTOM_PROFILE_TARGET" "$CUSTOM_PROFILE_BACKUP"
        echo "Backup created from existing custom.prf"
    else
        echo "No existing custom.prf found. Please create one first."
        exit 1
    fi
fi

# Ensure target directory exists
if [ ! -d "${LYNIS_DIR}/${LYNIS_VERSION}" ]; then
    echo "Error: Lynis directory ${LYNIS_DIR}/${LYNIS_VERSION} does not exist"
    exit 1
fi

# Restore the custom profile
if [ -f "$CUSTOM_PROFILE_BACKUP" ]; then
    cp "$CUSTOM_PROFILE_BACKUP" "$CUSTOM_PROFILE_TARGET"
    echo "✓ Custom Lynis profile restored to ${CUSTOM_PROFILE_TARGET}"
    
    # Verify it was restored
    if lynis show profiles 2>/dev/null | grep -q "custom.prf"; then
        echo "✓ Profile verified and active"
    else
        echo "Warning: Profile restored but not detected by lynis"
    fi
else
    echo "Error: Backup file not found at $CUSTOM_PROFILE_BACKUP"
    exit 1
fi

