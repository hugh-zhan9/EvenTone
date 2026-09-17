#!/usr/bin/env python3
"""Publish only when the remote release tag matches the built commit."""
import json
import os
import re
import subprocess
import sys
from pathlib import Path


def gh_json(*args):
    return json.loads(subprocess.check_output(["gh", "api", *args], text=True))


def resolve_tag(repo, tag, api=gh_json):
    refs = api(f"repos/{repo}/git/matching-refs/tags/{tag}")
    exact = [ref for ref in refs if ref["ref"] == f"refs/tags/{tag}"]
    if not exact:
        return None
    obj = exact[0]["object"]
    seen = set()
    while obj["type"] == "tag":
        if obj["sha"] in seen:
            raise ValueError("Cyclic annotated tag")
        seen.add(obj["sha"])
        obj = api(f"repos/{repo}/git/tags/{obj['sha']}")["object"]
    if obj["type"] != "commit":
        raise ValueError("Release tag must resolve to a commit")
    return obj["sha"]


def ensure_tag(repo, tag, sha, prerelease, api=gh_json):
    actual = resolve_tag(repo, tag, api)
    if actual is None and prerelease:
        api(f"repos/{repo}/git/refs", "--method", "POST",
            "-f", f"ref=refs/tags/{tag}", "-f", f"sha={sha}")
        actual = resolve_tag(repo, tag, api)
    if actual != sha:
        raise ValueError(f"Remote tag {tag} resolves to {actual}, expected {sha}; refusing release")


def releases_for_tag(repo, tag, api=gh_json):
    pages = api(f"repos/{repo}/releases?per_page=100", "--paginate", "--slurp")
    return [release for page in pages for release in page if release["tag_name"] == tag]


def publish(repo, tag, label, sha, prerelease, directory, api=gh_json, run=subprocess.run):
    if not re.fullmatch(r"[0-9a-f]{40}", sha):
        raise ValueError("Expected a full commit SHA")
    if not re.fullmatch(r"\d+\.\d+\.\d+(-preview\.[0-9a-f]{12})?", label):
        raise ValueError("Invalid release label")
    expected_tag = f"preview-{sha[:12]}" if prerelease else f"v{label}"
    if tag != expected_tag:
        raise ValueError("Release tag and label do not match the build")
    if releases_for_tag(repo, tag, api):
        raise ValueError(f"Release or draft already exists for {tag}; refusing to overwrite it")
    ensure_tag(repo, tag, sha, prerelease, api)
    created = api(f"repos/{repo}/releases", "--method", "POST", "-f", f"tag_name={tag}",
                  "-f", f"target_commitish={sha}", "-f", f"name=EvenTone {label}",
                  "-F", "draft=true", "-F", f"prerelease={str(prerelease).lower()}",
                  "-f", f"body={(directory / 'release-notes.md').read_text()}")
    if (not isinstance(created.get("id"), int) or not created.get("draft")
            or created.get("tag_name") != tag or created.get("target_commitish") != sha):
        raise ValueError("Unexpected create-release response; refusing publication")
    # Use the creation response ID instead of rediscovering the new draft via a list.
    for filename, content_type in [(f"EvenTone-{label}-macOS-arm64.zip", "application/zip"),
                                   ("SHA256SUMS.txt", "text/plain")]:
        url = f"https://uploads.github.com/repos/{repo}/releases/{created['id']}/assets?name={filename}"
        run(["gh", "api", url, "--method", "POST", "--header", f"Content-Type: {content_type}",
             "--input", str(directory / filename), "--silent"], check=True)
    # Detect a tag moved during asset upload before exposing the draft.
    ensure_tag(repo, tag, sha, False, api)
    args = ["gh", "api", f"repos/{repo}/releases/{created['id']}", "--method", "PATCH", "-F", "draft=false", "--silent"]
    if prerelease:
        args += ["-f", "make_latest=false"]
    run(args, check=True)
    print(f"Published https://github.com/{repo}/releases/tag/{tag}")


if __name__ == "__main__":
    try:
        flag = os.environ["IS_PRERELEASE"]
        if flag not in ("true", "false"):
            raise ValueError("IS_PRERELEASE must be true or false")
        publish(os.environ["GH_REPO"], os.environ["RELEASE_TAG"], os.environ["VERSION_LABEL"],
                os.environ["GITHUB_SHA"], flag == "true", Path(sys.argv[1]))
    except (ValueError, KeyError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
