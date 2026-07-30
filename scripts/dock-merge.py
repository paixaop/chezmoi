#!/usr/bin/env python3
"""Append managed applications to the Dock without taking ownership of it.

User-added tiles, folder stacks, and ordering are preserved: a managed app is
appended only when it is installed and not already present.
"""

from __future__ import annotations

import argparse
import os
import plistlib
import subprocess
import sys
from pathlib import Path
from urllib.parse import unquote, urlparse

MANAGED_APPS = [
    "/Applications/Thunderbird.app",
    "/Applications/Google Chrome.app",
    "/System/Cryptexes/App/System/Applications/Safari.app",
    "/Applications/Visual Studio Code.app",
    "/Applications/Cursor.app",
    "/Applications/ChatGPT.app",
    "/Applications/Microsoft Teams.app",
    "/Applications/rekordbox 7/rekordbox.app",
    "/Applications/DJ.Studio.app",
    "/Applications/Mixed In Key 11.app",
    "/Applications/Platinum Notes 10.app",
    "/System/Applications/Passwords.app",
    "/System/Applications/Notes.app",
    "/System/Applications/Utilities/Terminal.app",
    "/System/Applications/Messages.app",
    "/System/Applications/Calendar.app",
    "/System/Applications/Calculator.app",
    "/System/Applications/FaceTime.app",
    "/System/Applications/System Settings.app",
    "/System/Applications/FindMy.app",
    "/System/Applications/iPhone Mirroring.app",
]


def normalize(url_string: str) -> str:
    """Reduce a Dock tile URL or path to a comparable filesystem path."""
    if url_string.startswith("file://"):
        url_string = unquote(urlparse(url_string).path)
    return os.path.normpath(url_string).rstrip("/")


def tile(path: str) -> dict:
    return {
        "tile-data": {
            "file-data": {
                "_CFURLString": path,
                "_CFURLStringType": 0,
            },
            "file-label": Path(path).stem,
            "file-type": 41,
        },
        "tile-type": "file-tile",
    }


def existing_paths(persistent: list) -> set[str]:
    paths = set()
    for entry in persistent:
        url = (
            entry.get("tile-data", {})
            .get("file-data", {})
            .get("_CFURLString")
        )
        if isinstance(url, str) and url:
            paths.add(normalize(url))
    return paths


def merge_apps(persistent: list, apps: list[str], installed) -> tuple[list, list[str]]:
    """Return the merged tile list and the paths that were appended."""
    merged = list(persistent)
    present = existing_paths(merged)
    added = []
    for path in apps:
        key = normalize(path)
        if key in present:
            continue
        if not installed(path):
            continue
        merged.append(tile(path))
        present.add(key)
        added.append(path)
    return merged, added


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--plist",
        default=str(Path.home() / "Library/Preferences/com.apple.dock.plist"),
    )
    parser.add_argument("--no-restart", action="store_true")
    args = parser.parse_args()

    plist_path = Path(args.plist)
    if plist_path.exists():
        with plist_path.open("rb") as handle:
            dock = plistlib.load(handle)
    else:
        dock = {}

    persistent = dock.get("persistent-apps") or []
    merged, added = merge_apps(persistent, MANAGED_APPS, os.path.isdir)

    for path in MANAGED_APPS:
        if not os.path.isdir(path):
            print(f"!!  Dock skip (not installed): {path}", file=sys.stderr)

    if not added:
        print(f"==> Dock unchanged ({len(persistent)} apps kept)")
        return 0

    for path in added:
        print(f"==> Dock add: {path}")

    dock["persistent-apps"] = merged
    with plist_path.open("wb") as handle:
        plistlib.dump(dock, handle, fmt=plistlib.FMT_BINARY)

    print(f"==> Dock: added {len(added)}, kept {len(persistent)}")
    if not args.no_restart:
        subprocess.run(["killall", "Dock"], check=False)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
