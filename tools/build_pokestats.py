#!/usr/bin/env python3
import argparse
from contextlib import ExitStack
import json
from pathlib import Path
import subprocess
import sys
import tempfile

from pokestats_bundle import Bundle, ROOT, canonical, require, sha256, write_bundle

DEFAULT_DATASET = ROOT.parent / "pokeserver/recommendations"
KIND = "pokestats_recommendations"
LABEL = "Recommended"
BUCKET = "recommended"
NOTICE = (
    "Recommendations selected from usage statistics and factual game mechanics.\n"
    "Statistics: Smogon University, accessed through pkmn/smogon.\n"
    "https://www.smogon.com/stats/ https://github.com/pkmn/smogon\n"
    "Compatibility validation and factual data: Pokemon Showdown via @pkmn/sim.\n"
    "https://github.com/pkmn/ps https://github.com/smogon/pokemon-showdown\n"
    "Includes recommendations for species without usable usage statistics.\n"
    "No authored analysis movesets are included.\n"
)


def selected_set(species, row, generation):
    require(isinstance(row, dict), "Invalid selected set")
    require(isinstance(row.get("moves"), list) and all(isinstance(m, str) for m in row["moves"]),
            "Expected a single selected move combination")
    fields = {"moves": row["moves"], "level": row["level"], "ivs": row["ivs"]}
    if row["species"] != species:
        fields["species"] = row["species"]
    if generation >= 2 and row.get("item"):
        fields["item"] = row["item"]
    if generation >= 2 and row.get("gender"):
        fields["gender"] = row["gender"]
    if generation == 3:
        fields.update({name: row[name] for name in ("ability", "nature", "evs")})
    if any(move in ("Return", "Frustration") for move in row["moves"]):
        fields["happiness"] = row["happiness"]
    return fields


def read_sources(source):
    data, receipts = {}, {}
    for generation in (1, 2, 3):
        name = "gen%d.json" % generation
        raw = (Path(source) / name).read_bytes()
        require(len(raw) <= 16 * 1024 * 1024, "Source file too large")
        document = json.loads(raw)
        require(document.get("schemaVersion") == 1 and document.get("generation") == generation
                and document.get("status") == "completed", "Expected a completed generation export")
        records = document.get("pokemon")
        require(isinstance(records, dict) and records, "No recommendations in " + name)
        data[generation] = {}
        for species, record in records.items():
            require(record.get("species") == species and record.get("generation") == generation,
                    "Recommendation identity mismatch")
            data[generation][species] = selected_set(species, record["set"], generation)
        receipts[generation] = {"file": name, "sha256": sha256(raw)}
    return data, receipts


def validate_sets(data, node="node"):
    result = subprocess.run([node, str(ROOT / "tools/pokestats/validate.cjs")],
                            input=canonical({"generations": data}), stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=120)
    require(result.returncode == 0, result.stderr.decode().strip() or "Recommendation validation failed")
    return json.loads(result.stdout)


class Recommendations:
    def __init__(self, directory, key_file):
        self.directory = Path(directory).resolve()
        self.stack = ExitStack()
        try:
            raw = (self.directory / "dataset.json").read_bytes()
            require(len(raw) <= 32768, "Dataset manifest too large")
            self.manifest = json.loads(raw)
            require(self.manifest.get("schema") == 1 and self.manifest.get("kind") == KIND,
                    "Unsupported recommendation dataset")
            entries = self.manifest.get("generations")
            require(isinstance(entries, dict) and set(entries) == {"1", "2", "3"}, "Expected all three generations")
            self.bundles = {}
            for generation in (1, 2, 3):
                entry = entries[str(generation)]
                filename = "gen%d/gen%d.smg" % (generation, generation)
                require(entry["bundle"] == filename, "Invalid bundle path")
                bundle = self.stack.enter_context(Bundle(self.directory / filename, key_file))
                require(bundle.manifest["generation"] == generation
                        and bundle.manifest["provenance"].get("kind") == KIND
                        and bundle.manifest["provenance"].get("dataset_id") == self.manifest["dataset_id"],
                        "Bundle identity mismatch")
                require(sha256((self.directory / filename).read_bytes()) == entry["sha256"], "Bundle hash mismatch")
                verified = bundle.verify()
                require(verified["species"] == entry["species"] and verified["sets"] == entry["species"],
                        "Recommendation count mismatch")
                for species in bundle.manifest["index"]:
                    payload = bundle.query(species)
                    require(set(payload) == {"species", "formats"}
                            and set(payload["formats"]) == {BUCKET}
                            and set(payload["formats"][BUCKET]) == {LABEL},
                            "Expected recommendations only")
                self.bundles[generation] = bundle
        except BaseException:
            self.stack.close()
            raise

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.stack.close()

    def get(self, generation, species):
        require(generation in self.bundles, "Unsupported generation")
        payload = self.bundles[generation].query(species)
        if payload is None:
            return None
        fields = payload["formats"][BUCKET][LABEL]
        return {"generation": generation, "species": payload["species"],
                "set": {"species": payload["species"], **fields}}

    def species(self, generation):
        require(generation in self.bundles, "Unsupported generation")
        return [row["name"] for row in self.bundles[generation].manifest["index"].values()]

    def verify(self):
        return {"verified": True, "dataset_id": self.manifest["dataset_id"],
                "generations": {str(g): len(self.species(g)) for g in self.bundles},
                "recommendations": sum(len(self.species(g)) for g in self.bundles)}


def build(source, output, key_file, node="node"):
    output = Path(output).resolve()
    require(not output.exists(), "Output already exists; use a new dataset directory")
    data, receipts = read_sources(source)
    validator = validate_sets(data, node)
    dataset_id = sha256(canonical(data))
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".pokestats-", dir=output.parent) as temporary:
        stage = Path(temporary) / "dataset"
        stage.mkdir()
        manifest = {"schema": 1, "kind": KIND, "dataset_id": dataset_id, "generations": {}}
        for generation in (1, 2, 3):
            records = {species: {BUCKET: {LABEL: fields}} for species, fields in data[generation].items()}
            provenance = {"kind": KIND, "dataset_id": dataset_id, "generation": generation,
                          "branch": None, "commit": None, "editorial_sets_used": False,
                          "recommendations_only": True, "source": receipts[generation],
                          "source_sha256": receipts[generation]["sha256"],
                          "source_normalized_sha256": sha256(canonical(records)),
                          "importer_sha256": sha256(Path(__file__).read_bytes()),
                          "validator": validator}
            sidecars = {"ATTRIBUTION.txt": NOTICE.encode(), "pokemon-showdown.LICENSE.txt":
                        (ROOT / "tools/pokestats/node_modules/@pkmn/sim/LICENSE").read_bytes()}
            upstream_license = ROOT.parent / "smogon/LICENSE"
            if upstream_license.is_file():
                sidecars["pkmn-smogon.LICENSE.txt"] = upstream_license.read_bytes()
            write_bundle(records, provenance, sidecars, stage / ("gen%d" % generation), key_file, generation)
            filename = "gen%d/gen%d.smg" % (generation, generation)
            manifest["generations"][str(generation)] = {
                "bundle": filename, "sha256": sha256((stage / filename).read_bytes()),
                "species": len(records)}
        (stage / "dataset.json").write_bytes(canonical(manifest) + b"\n")
        with Recommendations(stage, key_file) as reader:
            summary = reader.verify()
            for generation in (1, 2, 3):
                for species, fields in data[generation].items():
                    require(reader.get(generation, species)["set"] == {"species": species, **fields},
                            "Recommendation round trip mismatch")
        require(not output.exists(), "Output appeared during build")
        stage.rename(output)
    return {"output": str(output), **summary}


def main():
    parser = argparse.ArgumentParser(description="Package and read selected Pokestats recommendations")
    commands = parser.add_subparsers(dest="command", required=True)
    builder = commands.add_parser("build")
    builder.add_argument("--source", type=Path, default=ROOT.parent / "pokestats/recommendations/output")
    builder.add_argument("--out", type=Path, default=DEFAULT_DATASET)
    builder.add_argument("--key-file", type=Path, required=True)
    builder.add_argument("--node", default="node")
    for name in ("verify", "query"):
        command = commands.add_parser(name)
        command.add_argument("--dataset", type=Path, default=DEFAULT_DATASET)
        command.add_argument("--key-file", type=Path, required=True)
        if name == "query":
            command.add_argument("--generation", type=int, choices=(1, 2, 3), required=True)
            command.add_argument("--species", required=True)
    args = parser.parse_args()
    try:
        if args.command == "build":
            result = build(args.source, args.out, args.key_file, args.node)
        else:
            with Recommendations(args.dataset, args.key_file) as reader:
                result = reader.verify() if args.command == "verify" else reader.get(args.generation, args.species)
                require(result is not None, "No recommendation for this species")
        print(json.dumps(result, indent=2, ensure_ascii=False))
        return 0
    except Exception as error:
        print("error: " + (str(error) or type(error).__name__), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
