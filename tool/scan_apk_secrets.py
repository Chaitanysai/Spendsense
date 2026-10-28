#!/usr/bin/env python3
"""Scan a built APK for bundled credential-shaped material.

Byte-oriented scan over every archive entry (binary files included). The
single independently reviewed Firebase Android client key is exempted from
the Google/Gemini-shaped pattern only, and only when its SHA-256 matches the
caller-supplied expected fingerprint, so editing google-services.json cannot
silently redefine which value is trusted. All other pattern matches fail.

Duplicate-category handling: the four patterns have mutually exclusive
literal prefixes (AIza / gsk_ / csk- / sk-or-), so no single value can match
two categories. If that ever changed, each category would still count and
report the match independently, and the Firebase exemption would apply only
to the google_gemini category.

Only counts and short SHA-256 fingerprints are ever printed; matched values
are never emitted to stdout, stderr, or error messages.
"""

import argparse
import hashlib
import json
import re
import sys
import zipfile
from pathlib import Path

PATTERNS = {
    "google_gemini": re.compile(rb"AIza[0-9A-Za-z_-]{35}"),
    "groq": re.compile(rb"gsk_[0-9A-Za-z]{40,}"),
    "cerebras": re.compile(rb"csk-[0-9A-Za-z]{40,}"),
    "openrouter": re.compile(rb"sk-or-[0-9A-Za-z-]{20,}"),
}
GOOGLE_KEY_SHAPE = re.compile(rb"\AAIza[0-9A-Za-z_-]{35}\Z")
ENV_ENTRY_NAMES = {".env"}

MAX_ENTRY_BYTES = 128 * 1024 * 1024
MAX_TOTAL_BYTES = 512 * 1024 * 1024
MAX_ENTRIES = 100_000


class ScanFailure(Exception):
    """Fail-closed configuration or archive problem (no match values inside)."""


def _sha256(value):
    return hashlib.sha256(value).hexdigest()


def _safe_fp(value):
    return _sha256(value)[:12]


def resolve_firebase_key(project_root):
    """Return the single reviewed Firebase Android client key, or raise.

    The key must be present, nonempty, shape-valid, and identical in
    android/app/google-services.json and lib/firebase_options.dart.
    """
    root = Path(project_root)
    google_path = root / "android" / "app" / "google-services.json"
    try:
        config = json.loads(google_path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        raise ScanFailure(
            "Firebase config check failed: android/app/google-services.json is missing")
    except (json.JSONDecodeError, OSError) as exc:
        raise ScanFailure(
            "Firebase config check failed: google-services.json is unreadable "
            f"or invalid JSON ({type(exc).__name__})")

    json_keys = {
        entry.get("current_key", "")
        for client in config.get("client", [])
        for entry in client.get("api_key", [])
        if entry.get("current_key")
    }
    if not json_keys:
        raise ScanFailure(
            "Firebase config check failed: no Android client API key in "
            "google-services.json")

    dart_path = root / "lib" / "firebase_options.dart"
    try:
        dart_text = dart_path.read_text(encoding="utf-8")
    except (FileNotFoundError, OSError) as exc:
        raise ScanFailure(
            "Firebase config check failed: lib/firebase_options.dart is "
            f"unreadable ({type(exc).__name__})")
    dart_keys = re.findall(r"apiKey:\s*['\"]([^'\"]+)['\"]", dart_text)
    if not dart_keys:
        raise ScanFailure(
            "Firebase config check failed: no apiKey in firebase_options.dart")

    all_keys = json_keys | set(dart_keys)
    if len(all_keys) != 1:
        raise ScanFailure(
            "Firebase config check failed: google-services.json and "
            "firebase_options.dart do not agree on a single client key")
    key = next(iter(all_keys))
    if not GOOGLE_KEY_SHAPE.fullmatch(key.encode("utf-8")):
        raise ScanFailure(
            "Firebase config check failed: configured client key does not "
            "have the expected Google-shaped syntax")
    return key


def scan_apk(apk_path, project_root=None, expected_sha256=None):
    """Scan one APK and return a redacted report dict.

    Report keys: violations, totals, exempt, unexpected_distinct,
    entries_scanned. A non-empty violations list means the scan failed.
    """
    if not expected_sha256:
        raise ScanFailure(
            "Firebase config check failed: expected SHA-256 assertion missing")
    expected_sha256 = expected_sha256.strip().lower()
    if not re.fullmatch(r"[0-9a-f]{64}", expected_sha256):
        raise ScanFailure(
            "Firebase config check failed: expected SHA-256 is not a 64-char "
            "hex digest")

    firebase_key = resolve_firebase_key(
        project_root if project_root else str(Path.cwd()))
    if _sha256(firebase_key.encode("utf-8")) != expected_sha256:
        raise ScanFailure(
            "Firebase config check failed: configured client key does not "
            "match the independently reviewed expected fingerprint")

    report = {
        "apk_path": str(apk_path),
        "entries_scanned": 0,
        "totals": {category: 0 for category in PATTERNS},
        "exempt": {"google_gemini": {"occurrences": 0, "distinct": 0}},
        "unexpected_distinct": {category: set() for category in PATTERNS},
        "violations": [],
    }

    apk = Path(apk_path)
    if not apk.is_file():
        report["violations"].append({
            "path": str(apk),
            "category": "archive",
            "occurrences": 0,
            "fingerprint": "-",
            "check": "APK file missing or unreadable",
        })
        return report

    try:
        with zipfile.ZipFile(apk) as archive:
            infos = archive.infolist()
            if len(infos) > MAX_ENTRIES:
                raise ScanFailure(
                    f"archive entry count {len(infos)} exceeds limit "
                    f"{MAX_ENTRIES}")
            total_bytes = 0
            for info in infos:
                if info.is_dir():
                    continue
                report["entries_scanned"] += 1
                if Path(info.filename).name in ENV_ENTRY_NAMES:
                    report["violations"].append({
                        "path": info.filename,
                        "category": "env_entry",
                        "occurrences": 1,
                        "fingerprint": "-",
                        "check": ".env entry is bundled inside the APK",
                    })
                if info.file_size > MAX_ENTRY_BYTES:
                    report["violations"].append({
                        "path": info.filename,
                        "category": "archive",
                        "occurrences": 0,
                        "fingerprint": "-",
                        "check": "archive entry exceeds the size limit",
                    })
                    continue
                total_bytes += info.file_size
                if total_bytes > MAX_TOTAL_BYTES:
                    raise ScanFailure(
                        "total uncompressed archive size exceeds limit")
                try:
                    data = archive.read(info)
                except (zipfile.BadZipFile, RuntimeError, OSError) as exc:
                    report["violations"].append({
                        "path": info.filename,
                        "category": "archive",
                        "occurrences": 0,
                        "fingerprint": "-",
                        "check": f"archive entry unreadable ({type(exc).__name__})",
                    })
                    continue
                _scan_entry(report, info.filename, data, firebase_key)
    except zipfile.BadZipFile as exc:
        report["violations"].append({
            "path": str(apk),
            "category": "archive",
            "occurrences": 0,
            "fingerprint": "-",
            "check": f"not a valid ZIP archive ({type(exc).__name__})",
        })
    except OSError as exc:
        report["violations"].append({
            "path": str(apk),
            "category": "archive",
            "occurrences": 0,
            "fingerprint": "-",
            "check": f"APK unreadable ({type(exc).__name__})",
        })

    for category, distinct in report["unexpected_distinct"].items():
        report["unexpected_distinct"][category] = len(distinct)
    report["exempt"]["google_gemini"]["distinct"] = \
        1 if report["exempt"]["google_gemini"]["occurrences"] else 0
    return report


def _scan_entry(report, path, data, firebase_key):
    firebase_bytes = firebase_key.encode("utf-8")
    for category, pattern in PATTERNS.items():
        matches = pattern.findall(data)
        if not matches:
            continue
        report["totals"][category] += len(matches)
        if category == "google_gemini" and firebase_key:
            exempt = sum(1 for value in matches if value == firebase_bytes)
            unexpected = [value for value in matches if value != firebase_bytes]
            if exempt:
                report["exempt"]["google_gemini"]["occurrences"] += exempt
            matches = unexpected
        if not matches:
            continue
        distinct = {_sha256(value) for value in matches}
        report["unexpected_distinct"][category] |= distinct
        fingerprints = sorted(_safe_fp(value) for value in matches)
        report["violations"].append({
            "path": path,
            "category": category,
            "occurrences": len(matches),
            "fingerprint": fingerprints[0] if len(fingerprints) == 1 else "-",
            "fingerprints": fingerprints,
            "check": "unexpected credential-pattern match",
        })


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apk_path", help="Path to the APK to scan")
    parser.add_argument(
        "--project-root", default=".",
        help="Project root containing android/ and lib/ (default: cwd)")
    parser.add_argument(
        "--expected-firebase-sha256", required=True,
        help="SHA-256 of the single reviewed Firebase Android client key")
    args = parser.parse_args(argv)

    try:
        report = scan_apk(
            args.apk_path, project_root=args.project_root,
            expected_sha256=args.expected_firebase_sha256)
    except ScanFailure as exc:
        print(f"[error] {exc}")
        return 1

    print("APK archive validated.")
    print(f"Archive entries scanned: {report['entries_scanned']}")
    print("Credential-pattern occurrences by category:")
    for category, count in report["totals"].items():
        print(f"  {category}: {count}")
    exempt = report["exempt"]["google_gemini"]
    if exempt["occurrences"]:
        print(
            "Reviewed Firebase client key: accepted "
            f"({exempt['occurrences']} occurrence(s), "
            f"{exempt['distinct']} distinct value)")
    env_hits = sum(
        1 for violation in report["violations"]
        if violation["category"] == "env_entry")
    if report["violations"]:
        for violation in report["violations"]:
            print(
                f"[error] {violation['check']}: entry={violation['path']}, "
                f"category={violation['category']}, "
                f"occurrences={violation['occurrences']}, "
                f"fingerprint={violation['fingerprint']}")
        print(f".env entries: {env_hits}")
        print("Unexpected credentials: present; scan failed.")
        return 1

    print("Unexpected credentials: none")
    print(f".env entries: {env_hits}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
