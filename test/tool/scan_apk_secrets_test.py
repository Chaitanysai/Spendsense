"""Regression tests for tool/scan_apk_secrets.py.

All credential-shaped strings in this file are synthetic placeholders. No
real API key, Firebase client key, or production secret appears anywhere.
"""

import hashlib
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT))

import tool.scan_apk_secrets as scanner  # noqa: E402

# Synthetic, obviously fake values. Lengths satisfy the scanner's shape
# rules so fixtures exercise the real matching code.
EXPECTED = "AIza" + "ABCDEFGHIJKLMNOPQRSTUVWXYZ012345678"  # 39 chars
UNEXPECTED = "AIza" + "ZYXWVUTSRQPONMLKJIHGFEDCBA987654321"  # 39 chars
GROQ = "gsk_" + "G" * 40
CEREBRAS = "csk-" + "C" * 40
OPENROUTER = "sk-or-" + "O" * 20
EXPECTED_SHA = hashlib.sha256(EXPECTED.encode("utf-8")).hexdigest()
UNEXPECTED_FP = hashlib.sha256(UNEXPECTED.encode("utf-8")).hexdigest()[:12]


def make_zip_bytes(entries):
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        for name, data in entries:
            zf.writestr(name, data)
    return buf.getvalue()


def write_project(root, key=EXPECTED, include_google_services=True,
                  include_dart=True):
    """Build a minimal project with Firebase config holding the given key."""
    app_dir = root / "android" / "app"
    lib_dir = root / "lib"
    app_dir.mkdir(parents=True)
    lib_dir.mkdir(parents=True)
    if include_google_services:
        google = {
            "project_info": {
                "project_number": "111111111111",
                "project_id": "synthetic-project",
                "storage_bucket": "synthetic-project.appspot.com",
            },
            "client": [{
                "client_info": {
                    "mobilesdk_app_id": "1:111111111111:android:aaaaaaaaaaaaaaaaaaaaaaaaaa",
                    "android_client_info": {"package_name": "com.example.synthetic"},
                },
                "api_key": [{"current_key": key}],
            }],
        }
        (app_dir / "google-services.json").write_text(json.dumps(google))
    if include_dart:
        (lib_dir / "firebase_options.dart").write_text(
            "static const FirebaseOptions android = FirebaseOptions(\n"
            f"  apiKey: '{key}',\n"
            "  appId: 'x',\n"
            ");\n")
    return root


def scan(entries, key=EXPECTED, expected_sha=EXPECTED_SHA, apk_name="candidate.apk"):
    """Build a synthetic APK and project, run the scanner, return its report."""
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp) / "proj"
        write_project(root, key=key)
        apk = root / apk_name
        apk.write_bytes(make_zip_bytes(entries))
        return scanner.scan_apk(
            str(apk), project_root=str(root), expected_sha256=expected_sha)


class ScanApkSecretsTest(unittest.TestCase):
    def assert_pass(self, report):
        self.assertEqual(report["violations"], [])

    def test_expected_firebase_key_only_passes(self):
        report = scan([("res/raw/config.bin", EXPECTED.encode("utf-8"))])
        self.assert_pass(report)
        self.assertEqual(report["totals"]["google_gemini"], 1)
        self.assertEqual(report["exempt"]["google_gemini"]["occurrences"], 1)
        self.assertEqual(report["exempt"]["google_gemini"]["distinct"], 1)

    def test_expected_plus_unexpected_aiza_fails_and_identifies_entry(self):
        report = scan([
            ("res/raw/config.bin", EXPECTED.encode("utf-8")),
            ("lib/leak.so", UNEXPECTED.encode("utf-8")),
        ])
        violations = report["violations"]
        self.assertEqual(len(violations), 1)
        self.assertEqual(violations[0]["path"], "lib/leak.so")
        self.assertEqual(violations[0]["category"], "google_gemini")
        self.assertEqual(violations[0]["occurrences"], 1)
        self.assertEqual(violations[0]["fingerprint"], UNEXPECTED_FP)

    def test_groq_shaped_string_fails(self):
        report = scan([("res/raw/config.bin", GROQ.encode("utf-8"))])
        self.assertEqual(report["violations"][0]["category"], "groq")

    def test_cerebras_shaped_string_fails(self):
        report = scan([("res/raw/config.bin", CEREBRAS.encode("utf-8"))])
        self.assertEqual(report["violations"][0]["category"], "cerebras")

    def test_openrouter_shaped_string_fails(self):
        report = scan([("res/raw/config.bin", OPENROUTER.encode("utf-8"))])
        self.assertEqual(report["violations"][0]["category"], "openrouter")

    def test_expected_key_five_times_in_binary_blob_passes_with_counts(self):
        blob = b"\x00\x01" + EXPECTED.encode("utf-8") + b"\x00" \
            + EXPECTED.encode("utf-8") * 4
        report = scan([("assets/flutter_assets/kernel_blob.bin", blob)])
        self.assert_pass(report)
        self.assertEqual(report["exempt"]["google_gemini"]["occurrences"], 5)
        self.assertEqual(report["exempt"]["google_gemini"]["distinct"], 1)

    def test_unexpected_google_string_in_binary_blob_without_newlines_fails(self):
        blob = b"\x00\x01\x02" + UNEXPECTED.encode("utf-8") + b"\xff\x00"
        report = scan([("assets/flutter_assets/kernel_blob.bin", blob)])
        self.assertEqual(len(report["violations"]), 1)
        self.assertEqual(report["violations"][0]["occurrences"], 1)

    def test_unexpected_credential_in_resources_arsc_entry_fails(self):
        report = scan([("resources.arsc", b"prefix" + UNEXPECTED.encode("utf-8"))])
        self.assertEqual(report["violations"][0]["path"], "resources.arsc")

    def test_missing_firebase_config_fails_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "proj"
            write_project(root, include_google_services=False)
            apk = root / "candidate.apk"
            apk.write_bytes(make_zip_bytes([("res/raw/config.bin", b"x")]))
            with self.assertRaises(scanner.ScanFailure):
                scanner.scan_apk(
                    str(apk), project_root=str(root), expected_sha256=EXPECTED_SHA)

    def test_invalid_firebase_json_fails_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "proj"
            write_project(root)
            (root / "android" / "app" / "google-services.json").write_text("{not json")
            apk = root / "candidate.apk"
            apk.write_bytes(make_zip_bytes([("res/raw/config.bin", b"x")]))
            with self.assertRaises(scanner.ScanFailure):
                scanner.scan_apk(
                    str(apk), project_root=str(root), expected_sha256=EXPECTED_SHA)

    def test_firebase_key_not_matching_expected_sha_fails_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "proj"
            write_project(root, key=UNEXPECTED)
            apk = root / "candidate.apk"
            apk.write_bytes(make_zip_bytes([("res/raw/config.bin", b"x")]))
            with self.assertRaises(scanner.ScanFailure):
                scanner.scan_apk(
                    str(apk), project_root=str(root), expected_sha256=EXPECTED_SHA)

    def test_firebase_key_with_wrong_shape_fails_closed(self):
        malformed = "not-a-key"
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "proj"
            write_project(root, key=malformed)
            apk = root / "candidate.apk"
            apk.write_bytes(make_zip_bytes([("res/raw/config.bin", b"x")]))
            with self.assertRaises(scanner.ScanFailure):
                scanner.scan_apk(
                    str(apk), project_root=str(root), expected_sha256=EXPECTED_SHA)

    def test_four_matching_chunks_of_one_value_are_one_distinct_value(self):
        payload = (UNEXPECTED + "\n") * 4
        report = scan([("res/raw/config.txt", payload.encode("utf-8"))])
        violations = report["violations"]
        self.assertEqual(len(violations), 1)
        self.assertEqual(violations[0]["occurrences"], 4)
        self.assertEqual(report["unexpected_distinct"]["google_gemini"], 1)

    def test_multiple_distinct_unexpected_values_reported_safely(self):
        second = "AIza" + "0" * 35
        second_fp = hashlib.sha256(second.encode("utf-8")).hexdigest()[:12]
        report = scan([
            ("a.bin", UNEXPECTED.encode("utf-8")),
            ("b.bin", second.encode("utf-8")),
        ])
        fingerprints = {v["fingerprint"] for v in report["violations"]}
        self.assertEqual(fingerprints, {UNEXPECTED_FP, second_fp})
        self.assertEqual(report["unexpected_distinct"]["google_gemini"], 2)
        for raw in (EXPECTED, UNEXPECTED, second):
            self.assertNotIn(raw, str(report))

    def test_not_a_zip_fails_safely(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "proj"
            write_project(root)
            apk = root / "candidate.apk"
            apk.write_bytes(b"this is not a zip archive")
            report = scanner.scan_apk(
                str(apk), project_root=str(root), expected_sha256=EXPECTED_SHA)
        self.assertEqual(len(report["violations"]), 1)

    def test_corrupted_archive_entry_fails_safely(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "proj"
            write_project(root)
            apk = root / "candidate.apk"
            name = "res/raw/data.bin"
            payload = b"payload-bytes" + UNEXPECTED.encode("utf-8")
            buf = io.BytesIO()
            with zipfile.ZipFile(buf, "w", zipfile.ZIP_STORED) as zf:
                zf.writestr(name, payload)
            raw = bytearray(buf.getvalue())
            raw[30 + len(name)] ^= 0xFF  # corrupt the stored member data
            apk.write_bytes(bytes(raw))
            report = scanner.scan_apk(
                str(apk), project_root=str(root), expected_sha256=EXPECTED_SHA)
        self.assertEqual(len(report["violations"]), 1)

    def test_dot_env_entry_fails(self):
        report = scan([("flutter_assets/.env", b"GROQ_API_KEY=\n")])
        self.assertEqual(len(report["violations"]), 1)
        self.assertIn(".env", report["violations"][0]["check"])

    def test_dot_env_example_with_empty_placeholders_does_not_fail(self):
        report = scan([("flutter_assets/.env.example",
                        b"GROQ_API_KEY=\nCEREBRAS_API_KEY=\n")])
        self.assert_pass(report)

    def test_no_credentials_passes(self):
        report = scan([("assets/sounds/click.wav", b"\x00\x01\x02")])
        self.assert_pass(report)
        self.assertEqual(sum(report["totals"].values()), 0)

    def test_non_google_patterns_are_not_firebase_exempt(self):
        report = scan([
            ("res/raw/config.bin", EXPECTED.encode("utf-8")),
            ("lib/leak.so", GROQ.encode("utf-8")),
        ])
        self.assertEqual([v["category"] for v in report["violations"]], ["groq"])
        self.assertEqual(report["exempt"]["google_gemini"]["occurrences"], 1)

    def test_entry_size_limit_enforced(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "proj"
            write_project(root)
            apk = root / "candidate.apk"
            apk.write_bytes(make_zip_bytes([("res/raw/big.bin", b"x" * 64)]))
            old = scanner.MAX_ENTRY_BYTES
            scanner.MAX_ENTRY_BYTES = 32
            try:
                report = scanner.scan_apk(
                    str(apk), project_root=str(root), expected_sha256=EXPECTED_SHA)
            finally:
                scanner.MAX_ENTRY_BYTES = old
        self.assertEqual(len(report["violations"]), 1)

    def test_cli_exits_nonzero_without_disclosing_values(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "proj"
            write_project(root)
            apk = root / "candidate.apk"
            apk.write_bytes(make_zip_bytes([("lib/leak.so", UNEXPECTED.encode("utf-8"))]))
            env = dict(os.environ)
            env["PYTHONPATH"] = str(REPO_ROOT)
            result = subprocess.run(
                [sys.executable, "-m", "tool.scan_apk_secrets",
                 str(apk), "--project-root", str(root),
                 "--expected-firebase-sha256", EXPECTED_SHA],
                capture_output=True, text=True, env=env)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn(UNEXPECTED, result.stdout)
        self.assertNotIn(UNEXPECTED, result.stderr)
        self.assertNotIn(EXPECTED, result.stdout)
        self.assertNotIn(EXPECTED, result.stderr)


if __name__ == "__main__":
    unittest.main()
