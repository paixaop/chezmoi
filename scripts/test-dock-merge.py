#!/usr/bin/env python3
"""Tests for the Dock merge behaviour: managed apps are added, nothing is lost."""

from __future__ import annotations

import importlib.util
import plistlib
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("dock-merge.py")

spec = importlib.util.spec_from_file_location("dock_merge", SCRIPT)
assert spec and spec.loader
dock_merge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dock_merge)


def folder_tile(path: str) -> dict:
    return {
        "tile-data": {"file-data": {"_CFURLString": path, "_CFURLStringType": 15}},
        "tile-type": "directory-tile",
    }


class MergeTests(unittest.TestCase):
    def test_appends_only_missing_installed_apps(self):
        existing = [dock_merge.tile("/Applications/Keep.app")]
        merged, added = dock_merge.merge_apps(
            existing,
            ["/Applications/Keep.app", "/Applications/New.app"],
            installed=lambda _: True,
        )
        self.assertEqual(added, ["/Applications/New.app"])
        self.assertEqual(len(merged), 2)

    def test_skips_apps_that_are_not_installed(self):
        merged, added = dock_merge.merge_apps(
            [], ["/Applications/Absent.app"], installed=lambda _: False
        )
        self.assertEqual(added, [])
        self.assertEqual(merged, [])

    def test_preserves_user_tiles_and_order(self):
        existing = [
            dock_merge.tile("/Applications/First.app"),
            folder_tile("file:///Users/someone/Downloads/"),
            dock_merge.tile("/Applications/Second.app"),
        ]
        merged, _ = dock_merge.merge_apps(
            existing, ["/Applications/Third.app"], installed=lambda _: True
        )
        self.assertEqual(merged[:3], existing)
        self.assertEqual(merged[3]["tile-data"]["file-label"], "Third")

    def test_matches_file_url_form_of_the_same_app(self):
        existing = [
            {
                "tile-data": {
                    "file-data": {
                        "_CFURLString": "file:///Applications/Google%20Chrome.app/",
                        "_CFURLStringType": 15,
                    }
                },
                "tile-type": "file-tile",
            }
        ]
        _, added = dock_merge.merge_apps(
            existing, ["/Applications/Google Chrome.app"], installed=lambda _: True
        )
        self.assertEqual(added, [])

    def test_does_not_duplicate_within_one_run(self):
        _, added = dock_merge.merge_apps(
            [],
            ["/Applications/Dup.app", "/Applications/Dup.app"],
            installed=lambda _: True,
        )
        self.assertEqual(added, ["/Applications/Dup.app"])


class CliTests(unittest.TestCase):
    def run_cli(self, plist_path: Path):
        return subprocess.run(
            [sys.executable, str(SCRIPT), "--plist", str(plist_path), "--no-restart"],
            capture_output=True,
            text=True,
            check=True,
        )

    def test_existing_entries_survive_a_real_plist_round_trip(self):
        with tempfile.TemporaryDirectory() as tmp:
            plist_path = Path(tmp) / "com.apple.dock.plist"
            original = {
                "persistent-apps": [dock_merge.tile("/Applications/UserPicked.app")],
                "persistent-others": [folder_tile("file:///Users/someone/Documents/")],
                "autohide": True,
            }
            with plist_path.open("wb") as handle:
                plistlib.dump(original, handle, fmt=plistlib.FMT_BINARY)

            self.run_cli(plist_path)

            with plist_path.open("rb") as handle:
                after = plistlib.load(handle)

            urls = [
                entry["tile-data"]["file-data"]["_CFURLString"]
                for entry in after["persistent-apps"]
            ]
            self.assertIn("/Applications/UserPicked.app", urls)
            self.assertEqual(after["persistent-others"], original["persistent-others"])
            self.assertTrue(after["autohide"])

    def test_second_run_makes_no_further_changes(self):
        with tempfile.TemporaryDirectory() as tmp:
            plist_path = Path(tmp) / "com.apple.dock.plist"
            with plist_path.open("wb") as handle:
                plistlib.dump({"persistent-apps": []}, handle, fmt=plistlib.FMT_BINARY)

            self.run_cli(plist_path)
            first = plist_path.read_bytes()
            result = self.run_cli(plist_path)

            self.assertEqual(first, plist_path.read_bytes())
            self.assertIn("unchanged", result.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
