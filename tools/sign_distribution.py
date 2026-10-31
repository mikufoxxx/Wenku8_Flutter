#!/usr/bin/env python3
"""Sign a reviewed draft's APKs with the repository's distribution credentials."""
from __future__ import annotations

import base64
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

VERSION = "0.5.4"
BUILD = 2274
MAX_APK_BYTES = 60_000_000
PACKAGE = "org.mewx.wenku8_flutter"
CERTIFICATE = "4e48d6854c5d8cc35685d982aae9fd8d573263405af0b6f5eb69dd26a8dc9f80"
ABIS = ("arm64-v8a", "armeabi-v7a", "x86_64")


def command(args, phase):
    result = subprocess.run(args, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(phase + " failed")
    return result.stdout


def check_package(badging, abi):
    expected = f"name='{PACKAGE}' versionCode='{BUILD}' versionName='{VERSION}'"
    if expected not in badging or "application-label:'轻小说文库'" not in badging:
        raise ValueError("Package identity or version mismatch")
    if "application-debuggable" in badging or f"native-code: '{abi}'" not in badging:
        raise ValueError("Release architecture or build type mismatch")


def main():
    repo = os.environ.get("GITHUB_REPOSITORY", "")
    if repo != "mikufoxxx/Wenku8_Flutter":
        raise ValueError("Unexpected repository")
    tag = os.environ.get("RELEASE_TAG", "")
    if tag != f"v{VERSION}":
        raise ValueError("Draft version needs publication review")
    release = json.loads(command(
        ["gh", "release", "view", tag, "-R", repo,
         "--json", "isDraft,isPrerelease,tagName,assets"], "Read draft"))
    if not release["isDraft"] or release["isPrerelease"] or release["tagName"] != tag:
        raise ValueError("Only the reviewed stable draft can be signed")
    expected_names = {f"unsigned-{abi}.apk" for abi in ABIS}
    actual_names = {asset["name"] for asset in release["assets"]}
    if actual_names != expected_names:
        raise ValueError("Draft input inventory mismatch")
    for asset in release["assets"]:
        if not 0 < asset["size"] <= MAX_APK_BYTES:
            raise ValueError("Draft input size mismatch")
    sdk = Path(os.environ["ANDROID_HOME"])
    candidates = [p for p in (sdk / "build-tools").iterdir()
                  if re.fullmatch(r"\d+\.\d+\.\d+", p.name) and (p / "apksigner").is_file()]
    tools = max(candidates, key=lambda p: tuple(map(int, p.name.split("."))))
    with tempfile.TemporaryDirectory(prefix="distribution-", dir=os.environ["RUNNER_TEMP"]) as temporary:
        root = Path(temporary)
        key = root / "distribution.jks"
        key.write_bytes(base64.b64decode(os.environ["ANDROID_KEYSTORE_BASE64"], validate=True))
        key.chmod(0o600)
        command(["gh", "release", "download", tag, "-R", repo, "--pattern",
                 "unsigned-*.apk", "--dir", str(root)], "Download draft")
        output = root / "signed"
        output.mkdir()
        for abi in ABIS:
            source = root / f"unsigned-{abi}.apk"
            metadata = next(asset for asset in release["assets"] if asset["name"] == source.name)
            if source.stat().st_size != metadata["size"]:
                raise ValueError("Downloaded input size mismatch")
            check_package(command([str(tools / "aapt"), "dump", "badging", str(source)],
                                  "Read package"), abi)
            destination = output / f"wenku8-{VERSION}-{abi}.apk"
            command([str(tools / "apksigner"), "sign", "--ks", str(key),
                     "--ks-key-alias", os.environ["ANDROID_KEY_ALIAS"],
                     "--ks-pass", "env:ANDROID_STORE_PASSWORD",
                     "--key-pass", "env:ANDROID_KEY_PASSWORD",
                     "--v4-signing-enabled", "false", "--out", str(destination),
                     str(source)], "Sign package")
            certificate = command([str(tools / "apksigner"), "verify", "--print-certs",
                                   str(destination)], "Verify package signature")
            if f"certificate SHA-256 digest: {CERTIFICATE}" not in certificate:
                raise ValueError("Distribution signing certificate mismatch")
            check_package(command([str(tools / "aapt"), "dump", "badging", str(destination)],
                                  "Read signed package"), abi)
            if destination.stat().st_size > MAX_APK_BYTES:
                raise ValueError("Signed package exceeds the release size budget")
            print(f"{abi}: verified {VERSION}+{BUILD}, {destination.stat().st_size} bytes")
        command(["gh", "release", "upload", tag, "-R", repo,
                 *map(str, sorted(output.glob("*.apk")))], "Upload signed packages")
    print("Signed APKs uploaded to the draft; publication remains a separate action.")


if __name__ == "__main__":
    main()
