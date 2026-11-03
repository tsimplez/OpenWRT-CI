#!/usr/bin/env python3
"""Resolve published honk/doona versions once for the current firmware build."""

import json
import os
from pathlib import Path
import re
import subprocess
import sys
from urllib.error import HTTPError
from urllib.request import Request, urlopen
import xml.etree.ElementTree as ET


VERSION = re.compile(r"v(\d+)\.(\d+)\.(\d+)(?:-(alpha|beta|rc)\.(\d+))?")


def version_key(tag):
    match = VERSION.fullmatch(tag)
    if not match:
        return None
    major, minor, patch, stage, number = match.groups()
    return (int(major), int(minor), int(patch),
            {"alpha": 0, "beta": 1, "rc": 2, None: 3}[stage], int(number or 0))


def fetch(url, *, api=False):
    headers = {"User-Agent": "OpenWRT-CI-honk"}
    if api:
        headers["Accept"] = "application/vnd.github+json"
        token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
        if token:
            headers["Authorization"] = f"Bearer {token}"
    with urlopen(Request(url, headers=headers), timeout=30) as response:
        return response.read().decode("utf-8")


def choose_release(releases):
    tags = [r["tag_name"] for r in releases
            if not r.get("draft") and version_key(r.get("tag_name", "")) is not None]
    if not tags:
        raise ValueError("no published stable/alpha/beta/rc release found")
    return max(tags, key=version_key)


def latest_release(repo):
    releases = []
    page = 1
    try:
        while True:
            batch = json.loads(fetch(
                f"https://api.github.com/repos/{repo}/releases?per_page=100&page={page}",
                api=True,
            ))
            releases.extend(batch)
            if len(batch) < 100:
                break
            page += 1
    except HTTPError as error:
        if error.code not in (403, 429):
            raise
        # Public release feeds also include prereleases and need no API quota.
        print(f"{repo}: API rate limited; reading the public release feed", file=sys.stderr)
        feed = ET.fromstring(fetch(f"https://github.com/{repo}/releases.atom"))
        prefix = f"https://github.com/{repo}/releases/tag/"
        releases = [
            {"tag_name": link.attrib["href"][len(prefix):]}
            for link in feed.findall("{http://www.w3.org/2005/Atom}entry/{http://www.w3.org/2005/Atom}link")
            if link.attrib.get("href", "").startswith(prefix)
        ]
    return choose_release(releases)


def tag_revision(repo, tag):
    ref = f"refs/tags/{tag}"
    result = subprocess.run(
        ["git", "ls-remote", "--tags", f"https://github.com/{repo}.git", ref, f"{ref}^{{}}"],
        check=True, capture_output=True, text=True, timeout=60,
    )
    refs = {name: sha for sha, name in (line.split() for line in result.stdout.splitlines())}
    revision = refs.get(f"{ref}^{{}}", refs.get(ref, ""))
    if not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise ValueError(f"{repo}: cannot resolve release tag {tag}")
    return revision


def checksum_for(checksums, filename):
    matches = []
    for line in checksums.splitlines():
        fields = line.split()
        if len(fields) == 2 and fields[1].lstrip("*").removeprefix("./") == filename:
            matches.append(fields[0])
    if len(matches) != 1 or not re.fullmatch(r"[0-9a-fA-F]{64}", matches[0]):
        raise ValueError(f"missing, duplicate or invalid SHA-256 for {filename}")
    return matches[0].lower()


def resolve_versions():
    honk_tag = latest_release("daeuniverse/honk")
    doona_tag = latest_release("Zakkaus/doona")
    doona_version = doona_tag.removeprefix("v")
    sums = fetch(f"https://github.com/Zakkaus/doona/releases/download/{doona_tag}/SHA256SUMS")
    return {
        "honk": {
            "tag": honk_tag,
            "revision": tag_revision("daeuniverse/honk", honk_tag),
            # OpenWrt apk uses 0.1.0_beta4 for upstream v0.1.0-beta.4.
            "package_version": re.sub(r"-(alpha|beta|rc)\.", r"_\1", honk_tag[1:]),
        },
        "doona": {
            "tag": doona_tag,
            "version": doona_version,
            "revision": tag_revision("Zakkaus/doona", doona_tag),
            "sha256": checksum_for(sums, f"doona-{doona_version}.tar.gz"),
            "lite_sha256": checksum_for(sums, f"doona-lite-{doona_version}.tar.gz"),
        },
    }


def main():
    versions = resolve_versions()
    Path(sys.argv[1]).write_text(json.dumps(versions, indent=2) + "\n", encoding="utf-8")
    print(f"honk: selected {versions['honk']['tag']}; doona: selected {versions['doona']['tag']}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, ET.ParseError, subprocess.SubprocessError) as error:
        sys.exit(f"honk: version resolution failed: {error}")
