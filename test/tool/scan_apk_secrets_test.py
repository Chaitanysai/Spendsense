"""Regression tests for tool/scan_apk_secrets.py.

All credential-shaped strings in this file are synthetic placeholders. No
real API key, Firebase client key, or production secret appears anywhere.
"""

import hashlib
import io
import json
import os
import re
import struct
import subprocess
import sys
import tempfile
import traceback
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

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


class ScannerCliReportingTest(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name) / "project"
        write_project(self.root)

    def run_cli(self, entries=(), *, raw_archive=None, apk_name="candidate.apk",
                extra_args=(), sensitive=(), expected_sha=EXPECTED_SHA):
        apk = self.root / apk_name
        apk.write_bytes(raw_archive if raw_archive is not None else make_zip_bytes(entries))
        args = [sys.executable, str(REPO_ROOT / "tool" / "scan_apk_secrets.py"),
                str(apk), "--project-root", str(self.root)]
        if expected_sha is not None:
            args.extend(["--expected-firebase-sha256", expected_sha])
        result = subprocess.run(
            args + list(extra_args), capture_output=True,
            encoding="utf-8", errors="replace", timeout=15)
        self.assert_redacted(result.stdout + result.stderr, sensitive)
        self.assertFalse("Traceback" in result.stderr, "unhandled CLI exception")
        return result

    def assert_redacted(self, text, additional=()):
        for value in (EXPECTED, UNEXPECTED, GROQ, CEREBRAS, OPENROUTER, *additional):
            self.assertFalse(value in text, "complete credential-shaped value disclosed")

    def assert_counts(self, output, category, expected):
        match = re.search(
            rf"^\s*{category}: occurrences=(\d+), distinct=(\d+), unexpected_distinct=(\d+)$",
            output, re.MULTILINE)
        self.assertTrue(match is not None, "category counts missing from CLI report")
        self.assertEqual(tuple(map(int, match.groups())), expected)

    def test_filename_only_credentials_fail_for_every_category(self):
        for category, value in (("google_gemini", UNEXPECTED), ("groq", GROQ),
                                ("cerebras", CEREBRAS), ("openrouter", OPENROUTER)):
            with self.subTest(category=category):
                name = f"assets/{value}/config.bin"
                result = self.run_cli([(name, b"ordinary content")])
                self.assertEqual(result.returncode, 1)
                self.assert_counts(result.stdout, category, (1, 1, 1))
                self.assertIn(f"category={category}", result.stdout)
                self.assertIn("source=filename", result.stdout)
                path_fp = hashlib.sha256(name.encode()).hexdigest()[:12]
                self.assertIn(f"path_sha256={path_fp}", result.stdout)
                self.assertIn("assets/", result.stdout)
                self.assertIn("/config.bin", result.stdout)

    def test_directory_name_credentials_are_not_skipped(self):
        result = self.run_cli([(f"assets/{GROQ}/", b"")])
        self.assertEqual(result.returncode, 1)
        self.assert_counts(result.stdout, "groq", (1, 1, 1))

    def test_credential_after_nul_is_scanned_and_original_name_is_hashed(self):
        name = f"assets/X{GROQ}.bin"
        raw = bytearray(make_zip_bytes([(name, b"empty")]))
        central = raw.index(b"PK\x01\x02")
        raw[30 + 7] = 0
        raw[central + 46 + 7] = 0
        original = name[:7] + "\x00" + name[8:]
        result = self.run_cli(raw_archive=bytes(raw))
        self.assertEqual(result.returncode, 1)
        self.assert_counts(result.stdout, "groq", (1, 1, 1))
        self.assertIn(r"\u0000", result.stdout)
        self.assertIn("path_sha256=" + hashlib.sha256(original.encode()).hexdigest()[:12],
                      result.stdout)

    def test_long_unicode_control_filename_is_bounded_and_escaped(self):
        long_value = "gsk_" + "L" * 10000
        name = ("assets/\u202e\u00e9\t\r\n\x1b/" + UNEXPECTED + "/" + UNEXPECTED
                + "/" + CEREBRAS + "/" + OPENROUTER + "/" + long_value + "/.env")
        result = self.run_cli([(name, b"empty")], sensitive=(long_value,))
        self.assertEqual(result.returncode, 1)
        self.assert_counts(result.stdout, "google_gemini", (2, 1, 1))
        self.assert_counts(result.stdout, "groq", (1, 1, 1))
        self.assert_counts(result.stdout, "cerebras", (1, 1, 1))
        self.assert_counts(result.stdout, "openrouter", (1, 1, 1))
        self.assertIn("category=env_entry", result.stdout)
        self.assertTrue(all(ord(c) < 128 for c in result.stdout))
        self.assertTrue(all(c == "\n" or ord(c) >= 32 for c in result.stdout))
        self.assertIn(r"\u202e", result.stdout)
        self.assertIn(r"\n", result.stdout)
        self.assertIn(r"\u00e9", result.stdout)
        self.assertLess(max(map(len, result.stdout.splitlines())), 1024)
        self.assertLess(len(result.stdout), 5000)
        self.assertIn(hashlib.sha256(name.encode()).hexdigest()[:12], result.stdout)

    def test_redacted_paths_remain_distinguishable_by_hash(self):
        second = "AIza" + "0" * 35
        names = [f"assets/{UNEXPECTED}.bin", f"assets/{second}.bin"]
        result = self.run_cli([(name, b"empty") for name in names], sensitive=(second,))
        self.assertEqual(result.returncode, 1)
        for name in names:
            self.assertIn("path_sha256=" + hashlib.sha256(name.encode()).hexdigest()[:12],
                          result.stdout)
        self.assert_counts(result.stdout, "google_gemini", (2, 2, 2))

    def test_binary_repeated_value_reports_one_fingerprint_and_four_occurrences(self):
        result = self.run_cli([("lib/repeated.bin", b"\x00".join([UNEXPECTED.encode()] * 4))])
        self.assertEqual(result.returncode, 1)
        self.assert_counts(result.stdout, "google_gemini", (4, 1, 1))
        self.assertIn("occurrences=4, distinct=1", result.stdout)
        self.assertEqual(result.stdout.count("fingerprints=" + UNEXPECTED_FP), 1)
        self.assertNotIn("fingerprint=-", result.stdout)

    def test_same_value_across_entries_has_global_distinct_count_one(self):
        result = self.run_cli([("a.bin", UNEXPECTED.encode()),
                               ("b.bin", b"\x00".join([UNEXPECTED.encode()] * 3))])
        self.assertEqual(result.returncode, 1)
        self.assert_counts(result.stdout, "google_gemini", (4, 1, 1))
        self.assertEqual(result.stdout.count("fingerprints=" + UNEXPECTED_FP), 2)

    def test_distinct_values_in_one_entry_each_have_a_fingerprint(self):
        second = "AIza" + "0" * 35
        payload = b"\x00".join([UNEXPECTED.encode(), second.encode(), UNEXPECTED.encode()])
        result = self.run_cli([("lib/multiple.bin", payload)], sensitive=(second,))
        self.assertEqual(result.returncode, 1)
        self.assert_counts(result.stdout, "google_gemini", (3, 2, 2))
        self.assertIn("occurrences=3, distinct=2", result.stdout)
        self.assertIn(UNEXPECTED_FP, result.stdout)
        self.assertIn(hashlib.sha256(second.encode()).hexdigest()[:12], result.stdout)
        self.assertNotIn("fingerprint=-", result.stdout)

    def test_short_hash_collision_does_not_merge_distinct_values(self):
        second = "AIza" + "0" * 35
        digests = {UNEXPECTED.encode(): "0123456789ab" + "0" * 52,
                   second.encode(): "0123456789ab" + "1" * 52}
        with patch.object(scanner, "_sha256", side_effect=lambda value:
                          digests.get(value, hashlib.sha256(value).hexdigest())):
            report = scan([("values.bin", b"\x00".join(digests))])
        self.assertEqual(report["totals"]["google_gemini"], 2)
        self.assertEqual(report["unexpected_distinct"]["google_gemini"], 2)
        self.assertEqual(report["violations"][0]["distinct"], 2)
        self.assertEqual(report["violations"][0]["fingerprints"], ["0123456789ab"])
        self.assert_redacted(json.dumps(report), (second,))

    def test_categories_are_counted_independently_with_no_non_google_exemption(self):
        payload = b"\x00".join(x.encode() for x in
                               (EXPECTED, UNEXPECTED, GROQ, GROQ, CEREBRAS, OPENROUTER))
        result = self.run_cli([("lib/mixed.bin", payload)])
        self.assertEqual(result.returncode, 1)
        self.assert_counts(result.stdout, "google_gemini", (2, 2, 1))
        self.assert_counts(result.stdout, "groq", (2, 1, 1))
        self.assert_counts(result.stdout, "cerebras", (1, 1, 1))
        self.assert_counts(result.stdout, "openrouter", (1, 1, 1))
        self.assertIn("accepted (1 occurrence(s), 1 distinct value)", result.stdout)
        for value in (UNEXPECTED, GROQ, CEREBRAS, OPENROUTER):
            self.assertIn(hashlib.sha256(value.encode()).hexdigest()[:12], result.stdout)

    def test_expected_and_unexpected_google_values_have_separate_counts(self):
        payload = b"\x00".join(x.encode() for x in (EXPECTED, EXPECTED, UNEXPECTED))
        result = self.run_cli([("resources.arsc", payload)])
        self.assertEqual(result.returncode, 1)
        self.assert_counts(result.stdout, "google_gemini", (3, 2, 1))
        self.assertIn("accepted (2 occurrence(s), 1 distinct value)", result.stdout)
        self.assertIn("fingerprints=" + UNEXPECTED_FP, result.stdout)

    def test_same_value_in_filename_and_content_counts_two_sources_one_value(self):
        result = self.run_cli([(f"assets/{UNEXPECTED}.bin", UNEXPECTED.encode())])
        self.assertEqual(result.returncode, 1)
        self.assert_counts(result.stdout, "google_gemini", (2, 1, 1))
        self.assertIn("source=filename", result.stdout)
        self.assertIn("source=content", result.stdout)
        self.assertEqual(result.stdout.count("fingerprints=" + UNEXPECTED_FP), 2)

    def test_only_expected_google_value_still_passes(self):
        result = self.run_cli([("resources.arsc", EXPECTED.encode())])
        self.assertEqual(result.returncode, 0)
        self.assert_counts(result.stdout, "google_gemini", (1, 1, 0))
        self.assertEqual(result.stderr, "")

    def test_non_zip_with_sensitive_apk_filename_reports_failure_safely(self):
        result = self.run_cli(raw_archive=b"not a ZIP", apk_name=UNEXPECTED + ".apk")
        self.assertEqual(result.returncode, 1)
        self.assertIn("category=archive", result.stdout)
        self.assertNotIn("APK archive validated.", result.stdout)

    def test_crc_failure_does_not_disclose_entry_name_or_exception(self):
        name = f"assets/{GROQ}/payload.bin"
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, "w", zipfile.ZIP_STORED) as archive:
            archive.writestr(name, b"payload")
        raw = bytearray(buf.getvalue())
        raw[30 + len(name)] ^= 0xFF
        result = self.run_cli(raw_archive=bytes(raw))
        self.assertEqual(result.returncode, 1)
        self.assertIn("category=archive", result.stdout)
        self.assertNotIn("APK archive validated.", result.stdout)

    def test_unsupported_compression_reports_safe_entry_error(self):
        raw = bytearray(make_zip_bytes([(f"assets/{CEREBRAS}.bin", b"payload")]))
        struct.pack_into("<H", raw, 8, 99)
        struct.pack_into("<H", raw, raw.index(b"PK\x01\x02") + 10, 99)
        result = self.run_cli(raw_archive=bytes(raw))
        self.assertEqual(result.returncode, 1)
        self.assertIn("category=archive", result.stdout)

    def test_corrupt_deflate_reports_safe_entry_error(self):
        name = f"assets/{GROQ}.bin"
        raw = bytearray(make_zip_bytes([(name, b"payload")]))
        raw[30 + len(name)] = 0x07
        result = self.run_cli(raw_archive=bytes(raw))
        self.assertEqual(result.returncode, 1)
        self.assertIn("category=archive", result.stdout)
        self.assertNotIn("APK archive validated.", result.stdout)

    def test_shared_local_header_fails_without_warning_disclosure(self):
        raw = make_zip_bytes([(f"assets/{GROQ}.bin", b"payload")])
        central = raw.index(b"PK\x01\x02")
        end = raw.index(b"PK\x05\x06")
        directory = raw[central:end]
        duplicate = bytearray(raw[:end] + directory + raw[end:])
        struct.pack_into("<HHI", duplicate, end + len(directory) + 8,
                         2, 2, 2 * len(directory))
        result = self.run_cli(raw_archive=bytes(duplicate))
        self.assertEqual(result.returncode, 1)
        self.assertIn("category=archive", result.stdout)
        self.assertNotIn("APK archive validated.", result.stdout)

    def test_missing_apk_returns_redacted_serializable_report(self):
        apk = self.root / (UNEXPECTED + ".apk")
        report = scanner.scan_apk(
            apk, project_root=self.root, expected_sha256=EXPECTED_SHA)
        self.assert_redacted(json.dumps(report))
        self.assertEqual(report["violations"][0]["category"], "archive")
        self.assertEqual(report["unexpected_distinct"]["google_gemini"], 0)
        self.assertEqual(report["apk_path_sha256"],
                         hashlib.sha256(str(apk).encode()).hexdigest()[:12])

    def test_invalid_utf8_entry_name_fails_without_traceback(self):
        raw = bytearray(make_zip_bytes([("name.bin", b"payload")]))
        central = raw.index(b"PK\x01\x02")
        struct.pack_into("<H", raw, 6, 0x800)
        struct.pack_into("<H", raw, central + 8, 0x800)
        raw[30] = 0xFF
        raw[central + 46] = 0xFF
        result = self.run_cli(raw_archive=bytes(raw), apk_name=OPENROUTER + ".apk")
        self.assertEqual(result.returncode, 1)

    def test_invalid_config_encoding_fails_without_traceback(self):
        (self.root / "android" / "app" / "google-services.json").write_bytes(
            b"\xff" + GROQ.encode())
        result = self.run_cli()
        self.assertEqual(result.returncode, 1)

    def test_malformed_config_structure_fails_without_traceback(self):
        (self.root / "android" / "app" / "google-services.json").write_text(
            json.dumps({"client": [GROQ]}))
        result = self.run_cli()
        self.assertEqual(result.returncode, 1)

    def test_config_exception_chain_does_not_disclose_sensitive_path(self):
        try:
            scanner.resolve_firebase_key(self.root / GROQ)
        except scanner.ScanFailure as exc:
            formatted = "".join(traceback.format_exception(exc))
        else:
            self.fail("missing config was accepted")
        self.assert_redacted(formatted)

    def test_missing_malformed_and_mismatched_fingerprint_fail_closed(self):
        for label, assertion in (("missing", None), ("malformed", GROQ),
                                 ("mismatch", "0" * 64)):
            with self.subTest(case=label):
                result = self.run_cli(expected_sha=assertion)
                self.assertNotEqual(result.returncode, 0)

    def test_unrecognized_cli_argument_does_not_echo_sensitive_value(self):
        result = self.run_cli(extra_args=("--unknown", GROQ))
        self.assertEqual(result.returncode, 2)


if __name__ == "__main__":
    unittest.main()
