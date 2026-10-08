#!/usr/bin/env python3
import hashlib
import hmac
import json
import os
from pathlib import Path
import re
import struct
import tempfile
import zlib

try:
    from cryptography.hazmat.primitives import hashes
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
    from cryptography.hazmat.primitives.kdf.hkdf import HKDF
except ImportError:
    raise SystemExit("Install tools/pokestats/requirements.txt in a virtual environment.")

ROOT = Path(__file__).resolve().parents[1]
MAGIC = b"G1RSMG01"
MAX_MANIFEST = 2 * 1024 * 1024
MAX_CHUNK = 1024 * 1024
MAX_BUNDLE = 64 * 1024 * 1024
STAT_KEYS = {"hp", "atk", "def", "spa", "spd", "spe"}
FIELDS = {"moves", "item", "nature", "ability", "evs", "ivs", "level", "species", "gender", "happiness"}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"),
                      ensure_ascii=False, allow_nan=False).encode("utf-8")


def sha256(body):
    return hashlib.sha256(body).hexdigest()


def species_id(name):
    return re.sub(r"[^a-z0-9]", "", name.lower())


def options(value):
    return value if isinstance(value, list) else [value]


def integer(value, low, high):
    return type(value) is int and low <= value <= high


def validate(data, generation=3):
    require(generation in (1, 2, 3), "Supported generations are 1, 2 and 3")
    require(isinstance(data, dict) and data, "Expected a nonempty generation sets object")
    seen = set()
    count = 0
    for species, formats in data.items():
        require(isinstance(species, str) and species_id(species), "Invalid species name")
        key = species_id(species)
        require(key not in seen, "Species ID collision: " + key)
        seen.add(key)
        require(isinstance(formats, dict) and formats, "Invalid formats for " + species)
        for tier, sets in formats.items():
            require(re.fullmatch(r"[a-z0-9]+", tier) is not None, "Invalid tier: " + tier)
            require(isinstance(sets, dict) and sets, "Empty or invalid sets")
            for name, row in sets.items():
                require(isinstance(name, str) and name, "Invalid set name")
                require(isinstance(row, dict) and set(row) <= FIELDS, "Unknown set fields: " + name)
                moves = row.get("moves")
                require(isinstance(moves, list) and 1 <= len(moves) <= 4, "Invalid move slots")
                for slot in moves:
                    require(options(slot) and all(isinstance(m, str) and m for m in options(slot)),
                            "Invalid move alternatives")
                for field in ("item", "nature", "ability"):
                    if field in row:
                        require(options(row[field]) and all(isinstance(v, str) and v
                                for v in options(row[field])), "Invalid " + field)
                for field, maximum in (("evs", 255), ("ivs", 31)):
                    for spread in options(row[field]) if field in row else []:
                        require(isinstance(spread, dict) and set(spread) <= STAT_KEYS,
                                "Invalid " + field + " spread")
                        require(all(integer(v, 0, maximum) for v in spread.values()),
                                "Invalid " + field + " value")
                        if field == "evs" and generation == 3:
                            require(sum(spread.values()) <= 510, "EV total exceeds 510")
                if "level" in row:
                    require(options(row["level"]) and all(integer(v, 1, 100)
                            for v in options(row["level"])), "Invalid level")
                if "species" in row:
                    require(isinstance(row["species"], str) and species_id(row["species"]), "Invalid species override")
                if "gender" in row:
                    require(row["gender"] in ("M", "F", "N"), "Invalid gender")
                if "happiness" in row:
                    require(integer(row["happiness"], 0, 255), "Invalid happiness")
                count += 1
    return count


def load_key(path):
    key = Path(path).read_bytes()
    require(len(key) == 32, "Key must be a raw 32-byte file")
    return key


def derive(key, salt):
    material = HKDF(algorithm=hashes.SHA256(), length=64, salt=salt,
                    info=b"gen1recomp/smogon/v1").derive(key)
    return material[:32], material[32:]


def write_bundle(data, provenance, sidecars, output, key_path, generation):
    output = Path(output).resolve()
    require(not output.exists(), "Output directory already exists; use a new snapshot directory")
    generation_id = "gen" + str(generation)
    sets = validate(data, generation)
    salt = os.urandom(32)
    enc_key, mac_key = derive(load_key(key_path), salt)
    chunks, index, offset = [], {}, 0
    for species in sorted(data, key=species_id):
        payload = {"species": species, "formats": data[species]}
        raw = canonical(payload)
        compressed = zlib.compress(raw, 9)
        require(len(raw) <= MAX_CHUNK and len(compressed) + 16 <= MAX_CHUNK, "Species chunk too large")
        nonce = os.urandom(12)
        key = species_id(species)
        index[key] = {"name": species, "formats": sorted(generation_id + tier for tier in data[species]),
                      "sets": sum(len(rows) for rows in data[species].values()),
                      "offset": offset, "length": len(compressed) + 16,
                      "decoded_length": len(raw), "sha256": sha256(raw), "nonce": nonce.hex()}
        chunks.append((key, nonce, compressed))
        offset += len(compressed) + 16
    require(all(re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", name) and isinstance(body, bytes)
                for name, body in sidecars.items()), "Invalid sidecar")
    require(not set(sidecars) & {generation_id + ".smg", "provenance.json"}, "Reserved sidecar name")
    manifest = {"schema": 1, "generation": generation, "cipher": "AES-256-GCM",
                "kdf": "HKDF-SHA256", "salt": salt.hex(), "compression": "zlib",
                "manifest_auth": "HMAC-SHA256", "species_count": len(index), "set_count": sets,
                "payload_bytes": offset, "index": index, "provenance": provenance,
                "sidecars": {name: sha256(body) for name, body in sidecars.items()}}
    header = canonical(manifest)
    require(len(header) <= MAX_MANIFEST and offset <= MAX_BUNDLE, "Bundle exceeds size limit")
    prefix = MAGIC + struct.pack("<I", len(header)) + header
    mac = hmac.digest(mac_key, prefix, "sha256")
    aad = hashlib.sha256(prefix).digest()
    encrypted = [AESGCM(enc_key).encrypt(nonce, body, aad + key.encode("ascii"))
                 for key, nonce, body in chunks]
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".pokestats-", dir=output.parent) as staging:
        stage = Path(staging) / "snapshot"
        stage.mkdir()
        (stage / (generation_id + ".smg")).write_bytes(prefix + mac + b"".join(encrypted))
        for name, body in sidecars.items():
            (stage / name).write_bytes(body)
        (stage / "provenance.json").write_bytes(canonical(provenance) + b"\n")
        with Bundle(stage / (generation_id + ".smg"), key_path) as bundle:
            bundle.verify()
        require(not output.exists(), "Output appeared during build")
        stage.rename(output)
    return {"output": str(output), "commit": provenance["commit"], "branch": provenance["branch"],
            "generation": generation, "species": len(index), "sets": sets,
            "bundle_bytes": (output / (generation_id + ".smg")).stat().st_size,
            "generated_sha256": sha256(canonical(data)), "source_sha256": provenance["source_sha256"]}


class Bundle:
    def __init__(self, path, key_path):
        self.path = Path(path)
        self.file = self.path.open("rb")
        try:
            first = self.file.read(12)
            require(len(first) == 12 and first[:8] == MAGIC, "Invalid bundle magic")
            size = struct.unpack("<I", first[8:])[0]
            require(0 < size <= MAX_MANIFEST, "Invalid manifest size")
            header = self.file.read(size)
            mac = self.file.read(32)
            require(len(header) == size and len(mac) == 32, "Truncated manifest")
            self.manifest = json.loads(header)
            salt = bytes.fromhex(self.manifest["salt"])
            require(len(salt) == 32, "Invalid salt")
            enc_key, mac_key = derive(load_key(key_path), salt)
            prefix = first + header
            require(hmac.compare_digest(mac, hmac.digest(mac_key, prefix, "sha256")),
                    "Manifest authentication failed (wrong key or tampered bundle)")
            self.aes = AESGCM(enc_key)
            self.aad = hashlib.sha256(prefix).digest()
            self.start = 12 + size + 32
            m = self.manifest
            require(m["generation"] in (1, 2, 3), "Unsupported generation")
            require((m["schema"], m["cipher"], m["kdf"], m["compression"], m["manifest_auth"])
                    == (1, "AES-256-GCM", "HKDF-SHA256", "zlib", "HMAC-SHA256"), "Unsupported schema")
            require(isinstance(m["index"], dict) and len(m["index"]) == m["species_count"], "Invalid species index")
            offset, nonces, count = 0, set(), 0
            for key, row in sorted(m["index"].items()):
                require(key == species_id(row["name"]) and key, "Invalid species key")
                require(row["offset"] == offset and integer(row["length"], 17, MAX_CHUNK)
                        and integer(row["decoded_length"], 1, MAX_CHUNK), "Invalid chunk bounds")
                nonce = bytes.fromhex(row["nonce"])
                require(len(nonce) == 12 and nonce not in nonces, "Invalid or reused nonce")
                nonces.add(nonce)
                offset += row["length"]
                count += row["sets"]
            require(offset <= MAX_BUNDLE and offset == m["payload_bytes"]
                    and count == m["set_count"], "Invalid payload totals")
            require(self.path.stat().st_size == self.start + offset, "Truncated or trailing payload")
        except BaseException:
            self.file.close()
            raise

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.file.close()

    def query(self, species, format_id=None):
        key = species_id(species)
        row = self.manifest["index"].get(key)
        if row is None:
            return None
        self.file.seek(self.start + row["offset"])
        ciphertext = self.file.read(row["length"])
        compressed = self.aes.decrypt(bytes.fromhex(row["nonce"]), ciphertext, self.aad + key.encode("ascii"))
        decoder = zlib.decompressobj()
        raw = decoder.decompress(compressed, row["decoded_length"] + 1)
        require(decoder.eof and not decoder.unused_data and len(raw) == row["decoded_length"]
                and sha256(raw) == row["sha256"], "Invalid decoded chunk")
        payload = json.loads(raw)
        require(payload["species"] == row["name"], "Species mismatch")
        if format_id is not None:
            prefix = "gen" + str(self.manifest["generation"])
            require(format_id.startswith(prefix) and re.fullmatch(r"gen[123][a-z0-9]+", format_id) is not None,
                    "Use a full format ID matching the bundle generation")
            payload["formats"] = {format_id[4:]: payload["formats"][format_id[4:]]} \
                if format_id[4:] in payload["formats"] else {}
        return payload

    def verify(self):
        data = {}
        for key, row in self.manifest["index"].items():
            payload = self.query(key)
            prefix = "gen" + str(self.manifest["generation"])
            require(sorted(prefix + tier for tier in payload["formats"]) == row["formats"], "Format index mismatch")
            require(validate({payload["species"]: payload["formats"]}, self.manifest["generation"])
                    == row["sets"], "Set count mismatch")
            data[payload["species"]] = payload["formats"]
        p = self.manifest["provenance"]
        require(sha256(canonical(data)) == p["source_normalized_sha256"], "Source round trip mismatch")
        for name, digest in self.manifest["sidecars"].items():
            require(re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", name) is not None, "Invalid sidecar path")
            require(sha256((self.path.parent / name).read_bytes()) == digest, "Sidecar mismatch: " + name)
        require(json.loads((self.path.parent / "provenance.json").read_bytes()) == p, "Provenance sidecar mismatch")
        return {"generation": self.manifest["generation"], "species": len(data),
                "sets": self.manifest["set_count"], "commit": p["commit"],
                "source_sha256": p["source_sha256"], "verified": True}
