import copy
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from cryptography.exceptions import InvalidTag

import pokestats_bundle as bundle_tool


DATA = {
    "Samplemon": {"ou": {"Sample set": {
        "moves": ["Sample Move", "Other Move", "Hidden Power Ice", "Last Move"],
        "item": "Sample Item", "nature": "Bold", "ability": "Sample Ability",
        "evs": {"hp": 252, "def": 252, "spa": 4},
        "ivs": {"atk": 30}}}, "lc": {"Little set": {"moves": ["Sample Move"], "level": 5}}},
    "Othermon": {"uu": {"Other set": {"moves": ["Other Move"], "ivs": {"atk": 0}}}},
}


class BundleTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.key = self.root / "key"
        self.key.write_bytes(bytes(range(32)))
        self.output = self.root / "snapshot"
        self.pack(self.output)
        self.path = self.output / "gen3.smg"

    def pack(self, output, data=DATA, generation=3):
        digest = bundle_tool.sha256(bundle_tool.canonical(data))
        provenance = {"kind": "pokestats_recommendations", "branch": "main", "commit": "a" * 40,
                      "source_sha256": digest, "source_normalized_sha256": digest}
        return bundle_tool.write_bundle(data, provenance, {"fixture.txt": b"Synthetic test fixture\n"},
                                   output, self.key, generation)

    def test_lossless_round_trip_and_provenance(self):
        with bundle_tool.Bundle(self.path, self.key) as bundle:
            self.assertEqual(bundle.verify()["sets"], 3)
            self.assertEqual(bundle.manifest["provenance"]["branch"], "main")
            self.assertEqual(bundle.manifest["provenance"]["source_sha256"], bundle_tool.sha256(bundle_tool.canonical(DATA)))
            self.assertEqual(bundle.query("SAMPLE-MON")["formats"], DATA["Samplemon"])
            self.assertEqual(bundle.query("Samplemon", "gen3ou")["formats"], {"ou": DATA["Samplemon"]["ou"]})
            self.assertEqual(bundle.query("Samplemon", "gen3ubers")["formats"], {})
            self.assertIsNone(bundle.query("Missingmon"))

    def test_query_reads_only_selected_chunk(self):
        with bundle_tool.Bundle(self.path, self.key) as bundle:
            real_file = bundle.file
            with patch.object(bundle, "file", wraps=real_file) as counted:
                bundle.query("Samplemon")
                counted.read.assert_called_once_with(bundle.manifest["index"]["samplemon"]["length"])

    def test_no_moves_in_cleartext(self):
        self.assertNotIn(b"Sample Move", self.path.read_bytes())
        self.assertNotIn(b"Hidden Power Ice", self.path.read_bytes())

    def test_wrong_key_rejected(self):
        wrong = self.root / "wrong"
        wrong.write_bytes(b"x" * 32)
        with self.assertRaisesRegex(ValueError, "authentication"):
            bundle_tool.Bundle(self.path, wrong)

    def test_manifest_tamper_rejected(self):
        body = self.path.read_bytes().replace(b'"set_count":3', b'"set_count":4', 1)
        self.path.write_bytes(body)
        with self.assertRaisesRegex(ValueError, "authentication"):
            bundle_tool.Bundle(self.path, self.key)

    def test_ciphertext_tamper_rejected(self):
        body = bytearray(self.path.read_bytes())
        with bundle_tool.Bundle(self.path, self.key) as bundle:
            body[bundle.start] ^= 1
        self.path.write_bytes(body)
        with bundle_tool.Bundle(self.path, self.key) as bundle:
            with self.assertRaises(InvalidTag):
                bundle.query("Othermon")

    def test_truncation_and_trailing_bytes_rejected(self):
        original = self.path.read_bytes()
        for body in (b"", original[:12], original[:-1], original + b"x"):
            with self.subTest(length=len(body)):
                self.path.write_bytes(body)
                with self.assertRaises(ValueError):
                    bundle_tool.Bundle(self.path, self.key)

    def test_sidecars_must_match(self):
        (self.output / "fixture.txt").write_bytes(b"changed")
        with bundle_tool.Bundle(self.path, self.key) as bundle:
            with self.assertRaisesRegex(ValueError, "Sidecar mismatch"):
                bundle.verify()

    def test_provenance_must_match(self):
        (self.output / "provenance.json").write_text("{}")
        with bundle_tool.Bundle(self.path, self.key) as bundle:
            with self.assertRaisesRegex(ValueError, "Provenance sidecar"):
                bundle.verify()

    def test_existing_output_not_overwritten(self):
        original = self.path.read_bytes()
        with self.assertRaisesRegex(ValueError, "already exists"):
            self.pack(self.output)
        self.assertEqual(self.path.read_bytes(), original)

    def test_fresh_encryption_per_build(self):
        other = self.root / "other"
        self.pack(other)
        self.assertNotEqual(self.path.read_bytes(), (other / "gen3.smg").read_bytes())
        with bundle_tool.Bundle(other / "gen3.smg", self.key) as bundle:
            self.assertEqual(bundle.query("Samplemon")["formats"], DATA["Samplemon"])

    def test_schema_errors_rejected(self):
        for field, value in (("moves", []), ("moves", [[], "x"]), ("evs", {"hp": 256}),
                             ("evs", {"hp": 255, "atk": 255, "spe": 1}),
                             ("ivs", {"hp": True}), ("ivs", {"hp": 32}),
                             ("level", 101), ("unknown", 1), ("item", [])):
            with self.subTest(field=field, value=value):
                data = copy.deepcopy(DATA)
                data["Samplemon"]["ou"]["Sample set"][field] = value
                with self.assertRaises(ValueError):
                    bundle_tool.validate(data)
        with self.assertRaisesRegex(ValueError, "collision"):
            bundle_tool.validate({"Othermon": DATA["Othermon"], "Other-mon": DATA["Othermon"]})

    def test_older_generations_preserve_stat_conventions(self):
        older = {"Samplemon": {"ou": {"Older set": {
            "moves": ["Sample Move", "Other Move", "Last Move"],
            "ivs": {"atk": 26, "def": 26},
            "evs": {key: 252 for key in bundle_tool.STAT_KEYS}}}}}
        for generation in (1, 2):
            with self.subTest(generation=generation):
                output = self.root / ("gen%d" % generation)
                self.pack(output, older, generation)
                with bundle_tool.Bundle(output / ("gen%d.smg" % generation), self.key) as bundle:
                    self.assertEqual(bundle.verify()["generation"], generation)
                    self.assertEqual(bundle.query("Samplemon", "gen%dou" % generation)["formats"], older["Samplemon"])
                    with self.assertRaisesRegex(ValueError, "matching the bundle"):
                        bundle.query("Samplemon", "gen3ou")
        with self.assertRaisesRegex(ValueError, "EV total"):
            bundle_tool.validate(older, generation=3)


if __name__ == "__main__":
    unittest.main()
