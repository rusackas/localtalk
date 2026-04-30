#!/usr/bin/env python3
"""
Append (or update) a single release entry in a Sparkle appcast.xml file.

Reads the private EdDSA key from stdin and pipes it to Sparkle's `sign_update`
helper to generate the per-file signature attribute. If an entry for the given
version already exists in the appcast, this is a no-op.

Usage:
    cat priv.key | append_appcast.py \\
        --appcast docs/appcast.xml \\
        --version 1.3.0 \\
        --dmg LocalTalk.dmg \\
        --url https://.../LocalTalk.dmg \\
        --notes-url https://github.com/.../releases/tag/v1.3.0 \\
        --sign-update .build/artifacts/sparkle/Sparkle/bin/sign_update
"""
import argparse
import os
import shlex
import subprocess
import sys
from datetime import datetime, timezone
from xml.etree import ElementTree as ET

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
SPARKLE = f"{{{SPARKLE_NS}}}"

ET.register_namespace("sparkle", SPARKLE_NS)


def parse_sign_update_output(text: str) -> dict:
    """sign_update prints space-separated `key="value"` attribute pairs."""
    attrs = {}
    for token in shlex.split(text.strip()):
        if "=" in token:
            k, v = token.split("=", 1)
            attrs[k] = v
    return attrs


def load_or_init_appcast(path: str) -> ET.ElementTree:
    if os.path.exists(path) and os.path.getsize(path) > 0:
        return ET.parse(path)
    rss = ET.Element("rss", attrib={"version": "2.0"})
    channel = ET.SubElement(rss, "channel")
    ET.SubElement(channel, "title").text = "LocalTalk"
    ET.SubElement(channel, "link").text = "https://github.com/rusackas/localtalk"
    ET.SubElement(channel, "description").text = "Updates for LocalTalk"
    ET.SubElement(channel, "language").text = "en"
    return ET.ElementTree(rss)


def already_present(channel: ET.Element, version: str) -> bool:
    for item in channel.findall("item"):
        enc = item.find("enclosure")
        if enc is None:
            continue
        if enc.get(f"{SPARKLE}version") == version or enc.get(f"{SPARKLE}shortVersionString") == version:
            return True
    return False


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--appcast", required=True)
    p.add_argument("--version", required=True)
    p.add_argument("--dmg", required=True)
    p.add_argument("--url", required=True)
    p.add_argument("--notes-url", default="")
    p.add_argument("--sign-update", required=True)
    args = p.parse_args()

    private_key = sys.stdin.read().strip()
    if not private_key:
        print("ERROR: no private key on stdin", file=sys.stderr)
        return 1

    sign_out = subprocess.run(
        [args.sign_update, "--ed-key-file", "-", args.dmg],
        input=private_key,
        text=True,
        capture_output=True,
        check=True,
    ).stdout
    attrs = parse_sign_update_output(sign_out)
    sig = attrs.get("sparkle:edSignature")
    length = attrs.get("length") or str(os.path.getsize(args.dmg))
    if not sig:
        print(f"ERROR: sign_update did not produce a signature: {sign_out!r}", file=sys.stderr)
        return 1

    tree = load_or_init_appcast(args.appcast)
    channel = tree.getroot().find("channel")

    if already_present(channel, args.version):
        print(f"Version {args.version} already present in {args.appcast} — no change.")
        return 0

    item = ET.Element("item")
    ET.SubElement(item, "title").text = f"Version {args.version}"
    if args.notes_url:
        link = ET.SubElement(item, f"{SPARKLE}releaseNotesLink")
        link.text = args.notes_url
    ET.SubElement(item, "pubDate").text = datetime.now(timezone.utc).strftime(
        "%a, %d %b %Y %H:%M:%S +0000"
    )
    ET.SubElement(
        item,
        "enclosure",
        attrib={
            "url": args.url,
            f"{SPARKLE}version": args.version,
            f"{SPARKLE}shortVersionString": args.version,
            "length": length,
            "type": "application/octet-stream",
            f"{SPARKLE}edSignature": sig,
        },
    )

    # Insert before any existing <item> so newest-first ordering is preserved.
    insert_at = len(list(channel))
    for i, child in enumerate(list(channel)):
        if child.tag == "item":
            insert_at = i
            break
    channel.insert(insert_at, item)

    ET.indent(tree, space="  ")
    tree.write(args.appcast, encoding="utf-8", xml_declaration=True)
    print(f"Added v{args.version} to {args.appcast}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
