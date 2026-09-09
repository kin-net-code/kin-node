#!/usr/bin/env python3
import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location(
    "kin_verify_canonical_base_test", ROOT / "host/verify_canonical_base.py")
base = importlib.util.module_from_spec(spec)
assert spec.loader
spec.loader.exec_module(base)


class CanonicalBaseTests(unittest.TestCase):
    VERSION = "20260823.0"

    def fixture(self):
        temporary = tempfile.TemporaryDirectory()
        provider = Path(temporary.name) / "virtualbox"
        provider.mkdir(mode=0o700)
        (provider / "metadata.json").write_text(
            '{"provider":"virtualbox"}\n', encoding="utf-8")
        (provider / "box.ovf").write_text("canonical-derived fixture\n",
                                          encoding="utf-8")
        receipt_dir = Path(temporary.name) / "root-admission"
        receipt_dir.mkdir(mode=0o700)
        receipt_path = receipt_dir / "kin-sanitized-ubuntu-26.04.json"
        receipt = {
            "schema": base.SCHEMA,
            "boxName": base.BOX_NAME,
            "boxProvider": base.BOX_PROVIDER,
            "boxVersion": self.VERSION,
            "boxTreeSha256": base.tree_digest(provider, expected_uid=os.getuid()),
            "source": base.SOURCE,
            "sanitization": base.SANITIZATION,
        }
        receipt_path.write_text(
            json.dumps(receipt, separators=(",", ":"), sort_keys=True) + "\n",
            encoding="utf-8")
        return temporary, provider, receipt_path

    def test_exact_receipt_and_tree_are_accepted(self):
        temporary, provider, receipt = self.fixture()
        try:
            observed = base.verify(
                provider, self.VERSION, receipt, expected_uid=os.getuid(),
                receipt_expected_uid=os.getuid())
            self.assertRegex(observed, r"^sha256:[0-9a-f]{64}$")
        finally:
            temporary.cleanup()

    def test_renamed_or_tampered_box_cannot_pass(self):
        temporary, provider, receipt_path = self.fixture()
        try:
            receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
            receipt["source"]["publisher"] = "Unreviewed third party"
            receipt_path.write_text(json.dumps(receipt), encoding="utf-8")
            with self.assertRaisesRegex(base.BaseImageError,
                                        "BASE_PROVENANCE_RECEIPT_CLAIM_INVALID"):
                base.verify(provider, self.VERSION, receipt_path,
                            expected_uid=os.getuid(), receipt_expected_uid=os.getuid())

            receipt["source"] = base.SOURCE
            receipt_path.write_text(json.dumps(receipt), encoding="utf-8")
            (provider / "box.ovf").write_text("tampered\n", encoding="utf-8")
            with self.assertRaisesRegex(base.BaseImageError,
                                        "BASE_TREE_DIGEST_MISMATCH"):
                base.verify(provider, self.VERSION, receipt_path,
                            expected_uid=os.getuid(), receipt_expected_uid=os.getuid())
        finally:
            temporary.cleanup()

    def test_missing_receipt_fails_closed(self):
        with tempfile.TemporaryDirectory() as temporary:
            provider = Path(temporary)
            receipt_dir = provider / "admission"
            receipt_dir.mkdir()
            with self.assertRaisesRegex(base.BaseImageError,
                                        "BASE_PROVENANCE_RECEIPT_ABSENT"):
                base.verify(provider, self.VERSION, receipt_dir / "missing.json",
                            expected_uid=os.getuid(), receipt_expected_uid=os.getuid())


if __name__ == "__main__":
    unittest.main()
