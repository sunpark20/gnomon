#!/usr/bin/env python3
"""Upload a binary asset to a GitHub draft release without exposing the auth token."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen


REPOSITORY = "sunpark20/gnomon"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("release_id", type=int)
    parser.add_argument("asset", type=Path)
    args = parser.parse_args()

    asset = args.asset
    payload = asset.read_bytes()
    token_result = subprocess.run(
        ["gh", "auth", "token"],
        check=True,
        capture_output=True,
        text=True,
    )
    token = token_result.stdout.strip()
    if not token:
        raise SystemExit("gh auth token returned an empty token")

    release_result = subprocess.run(
        ["gh", "api", f"repos/{REPOSITORY}/releases/{args.release_id}"],
        check=True,
        capture_output=True,
        text=True,
    )
    release = json.loads(release_result.stdout)
    upload_url = release["upload_url"].split("{", maxsplit=1)[0]
    upload_url = f"{upload_url}?name={quote(asset.name)}"
    request = Request(
        upload_url,
        data=payload,
        method="POST",
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/octet-stream",
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )
    try:
        with urlopen(request, timeout=120) as response:
            uploaded = json.load(response)
    except (HTTPError, URLError) as error:
        raise SystemExit(f"Could not upload {asset.name}: {error}") from error

    if uploaded.get("state") != "uploaded" or uploaded.get("size") != len(payload):
        raise SystemExit(f"GitHub did not confirm the complete upload of {asset.name}")
    print(f"Uploaded {asset.name} ({len(payload)} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
