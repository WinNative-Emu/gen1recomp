import copy
import json
import os
from pathlib import Path
import tempfile
import unittest

import build_pokestats as tool
from pokestats_bundle import Bundle, canonical, sha256, validate


class RecommendationsTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / "source"
        self.source.mkdir()
        self.key = self.root / "key"
        self.key.write_bytes(os.urandom(32))
        self.documents = {}
        for generation in (1, 2, 3):
            fields = {"species": "Venusaur", "name": "Venusaur", "level": 100,
                      "moves": ["Razor Leaf", "Body Slam", "Sleep Powder", "Swords Dance"],
                      "item": "Leftovers" if generation > 1 else "", "ability": "Overgrow",
                      "nature": "Adamant", "gender": "M", "happiness": 255,
                      "ivs": dict.fromkeys(("hp", "atk", "def", "spa", "spd", "spe"), 30 if generation == 2 else 31),
                      "evs": {"hp": 4, "atk": 252, "def": 0, "spa": 0, "spd": 0, "spe": 252}}
            self.documents[generation] = {"schemaVersion": 1, "generation": generation,
                                          "status": "completed", "pokemon": {"Venusaur": {
                                              "species": "Venusaur", "generation": generation, "set": fields,
                                              "evidence": {"excluded": "PRIVATE_EVIDENCE_FIXTURE"},
                                              "alternatives": ["PRIVATE_ALTERNATIVES_FIXTURE"],
                                              "construction": "PRIVATE_DECISIONS_FIXTURE"}}}
        self.write_sources()

    def write_sources(self):
        for generation, document in self.documents.items():
            (self.source / ("gen%d.json" % generation)).write_text(json.dumps(document))

    def pack(self, name="dataset"):
        output = self.root / name
        result = tool.build(self.source, output, self.key)
        self.assertEqual(result["recommendations"], 3)
        return output

    def test_recommendations_only_round_trip(self):
        output = self.pack()
        with tool.Recommendations(output, self.key) as reader:
            self.assertEqual(reader.verify()["recommendations"], 3)
            for generation in (1, 2, 3):
                actual = reader.get(generation, "VENUSAUR")
                expected = tool.selected_set("Venusaur", self.documents[generation]["pokemon"]["Venusaur"]["set"], generation)
                self.assertEqual(actual["set"], {"species": "Venusaur", **expected})
                self.assertEqual(reader.species(generation), ["Venusaur"])
                self.assertIsNone(reader.get(generation, "Pikachu"))
                with Bundle(output / ("gen%d/gen%d.smg" % (generation, generation)), self.key) as bundle:
                    self.assertEqual(set(bundle.query("Venusaur")), {"species", "formats"})
        for file in output.rglob("*"):
            if file.is_file():
                for marker in (b"PRIVATE_EVIDENCE_FIXTURE", b"PRIVATE_ALTERNATIVES_FIXTURE", b"PRIVATE_DECISIONS_FIXTURE"):
                    self.assertNotIn(marker, file.read_bytes())
        self.assertNotIn(b"Sleep Powder", (output / "gen3/gen3.smg").read_bytes())
        self.assertFalse(any("key" in file.name for file in output.rglob("*")))

    def test_wrong_key(self):
        output = self.pack()
        wrong = self.root / "wrong"
        wrong.write_bytes(os.urandom(32))
        with self.assertRaisesRegex(ValueError, "authentication failed"):
            tool.Recommendations(output, wrong)

    def test_tampered_ciphertext_even_with_updated_public_hash(self):
        output = self.pack()
        bundle = output / "gen1/gen1.smg"
        body = bytearray(bundle.read_bytes())
        body[-1] ^= 1
        bundle.write_bytes(body)
        manifest = json.loads((output / "dataset.json").read_bytes())
        manifest["generations"]["1"]["sha256"] = sha256(body)
        (output / "dataset.json").write_bytes(canonical(manifest))
        with self.assertRaises(Exception):
            tool.Recommendations(output, self.key)

    def test_partial_export_and_illegal_set_are_rejected(self):
        self.documents[1]["status"] = "running"
        self.write_sources()
        with self.assertRaisesRegex(ValueError, "completed"):
            self.pack()
        self.documents[1]["status"] = "completed"
        self.documents[1]["pokemon"]["Venusaur"]["set"]["moves"] = ["Spacial Rend"]
        self.write_sources()
        with self.assertRaises(ValueError):
            self.pack()
        self.assertFalse((self.root / "dataset").exists())

    def test_duplicate_moves_and_path_traversal_are_rejected(self):
        original = copy.deepcopy(self.documents)
        self.documents[3]["pokemon"]["Venusaur"]["set"]["moves"] = ["Razor Leaf", "Razor Leaf"]
        self.write_sources()
        with self.assertRaisesRegex(ValueError, "Duplicate"):
            self.pack()
        self.documents = original
        self.write_sources()
        output = self.pack()
        manifest = json.loads((output / "dataset.json").read_bytes())
        manifest["generations"]["1"]["bundle"] = "../outside.smg"
        (output / "dataset.json").write_bytes(canonical(manifest))
        with self.assertRaisesRegex(ValueError, "bundle path"):
            tool.Recommendations(output, self.key)

    def test_return_happiness_and_cosmetic_species_schema(self):
        fields = self.documents[3]["pokemon"]["Venusaur"]["set"]
        fields["moves"][1] = "Frustration"
        fields["happiness"] = 0
        self.write_sources()
        output = self.pack()
        with tool.Recommendations(output, self.key) as reader:
            self.assertEqual(reader.get(3, "Venusaur")["set"]["happiness"], 0)
        data = {"Unown": {"recommended": {"Recommended": {
            "moves": ["Hidden Power Psychic"], "species": "Unown-X", "gender": "N", "happiness": 0}}}}
        self.assertEqual(validate(data, 2), 1)
        for field, value in (("species", 1), ("gender", "other"), ("happiness", True), ("happiness", 256)):
            broken = copy.deepcopy(data)
            broken["Unown"]["recommended"]["Recommended"][field] = value
            with self.assertRaises(ValueError):
                validate(broken, 2)

    def test_existing_snapshot_is_not_overwritten(self):
        output = self.pack()
        before = (output / "gen1/gen1.smg").read_bytes()
        with self.assertRaisesRegex(ValueError, "already exists"):
            tool.build(self.source, output, self.key)
        self.assertEqual((output / "gen1/gen1.smg").read_bytes(), before)


if __name__ == "__main__":
    unittest.main()
