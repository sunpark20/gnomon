#!/usr/bin/env python3
"""Create the signed-update feed entry for a Gnomon release."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
from email.utils import format_datetime
from pathlib import Path
import re
import xml.etree.ElementTree as ET


SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
RELEASE_REPOSITORY = "https://github.com/sunpark20/gnomon"
ET.register_namespace("sparkle", SPARKLE_NS)


def create_appcast(
    *,
    version_tag: str,
    build_number: str,
    asset_name: str,
    asset_length: int,
    signature: str,
    published_at: datetime | None = None,
) -> ET.ElementTree:
    if not re.fullmatch(r"v\d+\.\d+\.\d+", version_tag):
        raise ValueError("version tag must use vMAJOR.MINOR.PATCH")
    if not re.fullmatch(r"\d+", build_number):
        raise ValueError("build number must be numeric")
    if not re.fullmatch(r"[A-Za-z0-9._-]+\.dmg", asset_name):
        raise ValueError("asset must be a DMG filename")
    if not re.fullmatch(r"[A-Za-z0-9+/]{86}==", signature):
        raise ValueError("signature must be a base64 Ed25519 signature")
    if asset_length <= 0:
        raise ValueError("asset length must be positive")

    version = version_tag[1:]
    timestamp = published_at or datetime.now(timezone.utc)
    release_url = f"{RELEASE_REPOSITORY}/releases/download/{version_tag}/{asset_name}"

    rss = ET.Element("rss", {"version": "2.0"})
    channel = ET.SubElement(rss, "channel")
    ET.SubElement(channel, "title").text = "Gnomon updates"
    ET.SubElement(channel, "link").text = f"{RELEASE_REPOSITORY}/releases"
    ET.SubElement(channel, "description").text = "Signed Gnomon application updates"

    item = ET.SubElement(channel, "item")
    ET.SubElement(item, "title").text = f"Gnomon {version_tag}"
    ET.SubElement(item, f"{{{SPARKLE_NS}}}version").text = build_number
    ET.SubElement(item, f"{{{SPARKLE_NS}}}shortVersionString").text = version
    ET.SubElement(item, f"{{{SPARKLE_NS}}}minimumSystemVersion").text = "15.0"
    ET.SubElement(item, "pubDate").text = format_datetime(timestamp)
    ET.SubElement(item, "link").text = f"{RELEASE_REPOSITORY}/releases/tag/{version_tag}"
    ET.SubElement(item, "description").text = f"Gnomon {version_tag} update"
    ET.SubElement(
        item,
        "enclosure",
        {
            "url": release_url,
            f"{{{SPARKLE_NS}}}edSignature": signature,
            "length": str(asset_length),
            "type": "application/octet-stream",
        },
    )
    return ET.ElementTree(rss)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build-number", required=True)
    parser.add_argument("--asset", required=True, type=Path)
    parser.add_argument("--signature", required=True)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    tree = create_appcast(
        version_tag=args.version,
        build_number=args.build_number,
        asset_name=args.asset.name,
        asset_length=args.asset.stat().st_size,
        signature=args.signature.strip(),
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    ET.indent(tree, space="  ")
    tree.write(args.output, encoding="utf-8", xml_declaration=True)
    print(f"Created Gnomon appcast: {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
