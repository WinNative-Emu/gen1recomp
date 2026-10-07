#!/usr/bin/env python3
"""Build the ROM-free PortMaster catalogue submission from this checkout."""
import argparse
import datetime
import json
from pathlib import Path
import re
import shutil
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[2]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True)
    parser.add_argument("--screenshot", type=Path, required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", args.version):
        parser.error("version must be X.Y.Z")
    screenshot = args.screenshot.resolve()
    if not screenshot.is_file() or screenshot.suffix.lower() not in (".png", ".jpg"):
        parser.error("screenshot must be an existing PNG or JPG gameplay capture")
    output = ROOT / "dist/portmaster"
    port = output / "ports/gen1recomp"
    if port.exists():
        shutil.rmtree(port)
    game = port / "gen1recomp"
    game.mkdir(parents=True)
    payload = output / "game.love"
    subprocess.run([str(ROOT / "scripts/pack_love.sh"), "--output", str(payload),
                    "--listing", str(output / "payload-listing.txt"),
                    "--version", args.version], check=True)
    with zipfile.ZipFile(payload) as archive:
        for name in archive.namelist():
            path = Path(name)
            if (path.is_absolute() or ".." in path.parts
                    or path.suffix.lower() in (".gb", ".gbc", ".gba", ".sav", ".srm", ".bak")
                    or "generated" in path.parts or "updates" in path.parts):
                raise SystemExit(f"Private/generated payload entry rejected: {name}")
        archive.extractall(game / "lovegame")
    # These development helpers are not used by the game and cause firmware
    # frontends to discover extra launch entries inside the port directory.
    for helper in ("src/import/gba/install_local_rom.sh",
                   "src/import/gba/chrome/vendor_ui.sh"):
        (game / "lovegame" / helper).unlink(missing_ok=True)
    (game / "lovegame/portable.txt").touch()
    licenses = game / "licenses"
    licenses.mkdir()
    shutil.copy2(ROOT / "LICENSE.MD", licenses / "LICENSE.MD")
    shutil.copy2(ROOT / "assets/launcher/lucide/LICENSE", licenses / "lucide.txt")
    for notice in (ROOT / "scripts/portmaster/licenses").glob("*.txt"):
        shutil.copy2(notice, licenses / notice.name)
    for notice in ("fonts/plainpixel", "skins/gba_purple", "skins/gb_anim",
                   "skins/tv_crt", "touch", "game3"):
        shutil.copy2(ROOT / "assets" / notice / "README.md",
                     licenses / (notice.replace("/", "-") + ".md"))
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    dirty = bool(subprocess.check_output(["git", "status", "--porcelain", "--untracked-files=no"], cwd=ROOT))
    (game / "SOURCE.txt").write_text(
        f"https://github.com/bryanthaboi/gen1recomp\nRevision: {revision}\n"
        f"Version: {args.version}\nTracked working-tree changes: {dirty}\n"
        "Testing candidate; hardware validation pending.\n")
    for name in ("Gen1Recomp.sh", "README.md"):
        shutil.copy2(ROOT / "scripts/portmaster" / name, port / name)
    (port / "Gen1Recomp.sh").chmod(0o755)
    shutil.copy2(screenshot, port / ("screenshot" + screenshot.suffix.lower()))
    metadata = {
        "version": 4, "name": "gen1recomp.zip",
        "items": ["Gen1Recomp.sh", "gen1recomp"], "items_opt": [],
        "attr": {"title": "Gen1Recomp", "porter": ["Nexhas28"],
                 "desc": "Native Pokemon recreation in LÖVE. Requires your own supported US ROM; no ROM is included.",
                 "desc_md": None,
                 "inst": "Copy a supported canonical US ROM into gen1recomp/lovegame/, then launch and choose the ROM. Start with Red or Blue. Update through PortMaster.",
                 "inst_md": None, "genres": ["adventure", "rpg"], "image": None,
                 "rtr": False, "exp": False, "runtime": [], "store": [],
                 "reqs": [], "arch": ["aarch64"], "min_glibc": ""}}
    (port / "port.json").write_text(json.dumps(metadata, indent=4) + "\n")
    date = datetime.date.today().strftime("%Y%m%d")
    (port / "gameinfo.xml").write_text(f'''<?xml version="1.0" encoding="utf-8"?>
<gameList><game>
<path>./Gen1Recomp.sh</path><name>Gen1Recomp</name>
<desc>Native Pokemon recreation. Supply your own supported US ROM.
Based on the Pokemon Gen 1 Recompilation Project by BOIS CLUB GAMES, LLC
(https://github.com/bryanthaboi/gen1recomp)</desc>
<releasedate>{date}T000000</releasedate><developer>BOIS CLUB GAMES, LLC</developer>
<publisher>BOIS CLUB GAMES, LLC</publisher><genre>RPG</genre>
<image>./gen1recomp/screenshot{screenshot.suffix.lower()}</image>
</game></gameList>
''')
    with zipfile.ZipFile(output / "gen1recomp-testing.zip", "w", zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(port.rglob("*")):
            if path.is_file():
                relative = path.relative_to(port)
                # Match PortMaster's build_release.py install layout.
                if len(relative.parts) == 1 and relative.name != "Gen1Recomp.sh":
                    name = "gen1recomp.md" if relative.name == "README.md" else relative.name
                    relative = Path("gen1recomp") / name
                archive.write(path, relative)
    print(port)
    print(output / "gen1recomp-testing.zip")

if __name__ == "__main__":
    main()
