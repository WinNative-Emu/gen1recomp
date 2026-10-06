#!/usr/bin/env python3
"""Generate/check RS constants, native symbols for all six USA builds, and manifests.

python3 tools/gen_rs_foundation.py [--pret ../pokeruby] [--check]
Requires matching pret ROMs and ELFs plus arm-none-eabi-readelf. No ROM bytes
are copied into generated artifacts. --check writes only to a temporary folder.
"""

import argparse
import hashlib
import json
import subprocess
import sys
import tempfile
from pathlib import Path

import gen_gba_constants as constants
import gen_gba_syms as symbols
import gen_rs_script_catalog as script_catalog

ROOT = Path(__file__).resolve().parent.parent


def generate(pret, output):
    for game in ("ruby", "sapphire"):
        for rev in range(3):
            suffix = "_rev" + str(rev) if rev else ""
            stem = "poke" + game + suffix
            build = game + ("1" + str(rev) if rev else "")
            data = (pret / (stem + ".gba")).read_bytes()
            expected = (pret / (game + suffix + ".sha1")).read_text().split()[0]
            actual = hashlib.sha1(data).hexdigest()
            if actual != expected or len(data) != 16777216:
                raise ValueError(f"{stem}: ROM does not match pret's expected USA build")
            print(f"verified {build} {actual}")
            rows = symbols.read_symbols(str(pret / (stem + ".elf")))
            symbols.fill_spans(rows)
            for kind, ending in (("data", ""), ("func", "_funcs")):
                selected = [r for r in rows if (r["type"] == "FUNC") == (kind == "func")]
                body = symbols.render(build, stem + ".elf", kind, *symbols.build(selected))
                path = output / "src/import/gba/syms" / (build + ending + ".lua")
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(body)
            if rev == 0:
                path = output / "tools" / ("rom_manifest_" + game + ".json")
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(json.dumps({"romSha1": actual, "charmap": {}, "symbols": {}}, indent=2) + "\n")

    previous = constants.OUT_ROOT
    constants.OUT_ROOT = str(output / "src/core/game3/constants")
    try:
        pret_str = str(pret)
        for kind, fn in (("specials", constants.gen_specials), ("script_cmds", constants.gen_script_cmds)):
            data, sources = fn("ruby", pret_str)
            constants.write_lua("ruby", kind, sources, data)
        headers = constants.headers(pret_str)
        for kind, fn, hex_format in constants.HDR_KINDS:
            data, sources = fn("ruby", headers, pret_str)
            constants.write_lua("ruby", kind, sources, data, hex_format)
    finally:
        constants.OUT_ROOT = previous
    text_path = output / "src/import/gba/versions_text_rs.lua"
    text_path.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([sys.executable, str(ROOT / "tools/gen_rom_text_tables.py"),
                    "--game", "ruby", "--repo", str(pret), "--out", str(text_path)], check=True)
    script_catalog.generate(pret, output / "src/import/gba/versions_scripts_rs.lua")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pret", type=Path, default=ROOT.parent / "pokeruby")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    pret = args.pret.resolve()
    if not args.check:
        generate(pret, ROOT)
        return 0
    with tempfile.TemporaryDirectory(prefix="rs-foundation-") as folder:
        output = Path(folder)
        generate(pret, output)
        differences = []
        files = sorted(p for p in output.rglob("*") if p.is_file())
        for generated in files:
            relative = generated.relative_to(output)
            saved = ROOT / relative
            if not saved.is_file() or saved.read_bytes() != generated.read_bytes():
                differences.append(str(relative))
        if differences:
            print("DIFF\n" + "\n".join(differences))
            return 1
        print(f"PASS {len(files)} generated artifacts match all six native builds")
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
