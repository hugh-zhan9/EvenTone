#!/usr/bin/env python3
"""Validate the release version and derive safe workflow outputs."""
import os
import plistlib
import re
import sys
from pathlib import Path


def metadata(plist, event, ref, sha):
    version = plist.get("CFBundleShortVersionString", "")
    if not isinstance(version, str) or not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("CFBundleShortVersionString must be X.Y.Z")
    if not re.fullmatch(r"[0-9a-f]{40}", sha):
        raise ValueError("Expected a full commit SHA")
    publish = event == "push" and (ref == "refs/heads/main" or ref.startswith("refs/tags/v"))
    stable = publish and ref.startswith("refs/tags/v")
    if stable and ref != f"refs/tags/v{version}":
        raise ValueError(f"Release tag must match Info.plist: v{version}")
    return {
        "version": version,
        "tag": f"v{version}" if stable else f"preview-{sha[:12]}",
        "label": version if stable else f"{version}-preview.{sha[:12]}",
        "publish": str(publish).lower(),
        "prerelease": str(not stable).lower(),
    }


if __name__ == "__main__":
    try:
        path = Path(__file__).resolve().parent.parent / "Resources/Info.plist"
        with path.open("rb") as source:
            values = metadata(plistlib.load(source), os.environ["GITHUB_EVENT_NAME"],
                              os.environ["GITHUB_REF"], os.environ["GITHUB_SHA"])
        for key, value in values.items():
            print(f"{key}={value}")
    except (ValueError, KeyError) as error:
        sys.exit(str(error))
