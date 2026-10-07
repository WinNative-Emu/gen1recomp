#!/usr/bin/env python3
import json
import os
import re
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEV = os.path.abspath(os.path.join(HERE, "..", ".."))
PKHEX = os.environ.get("PKHEX", os.path.join(DEV, "pkhex-master", "PKHeX.Core"))
SERVER = os.environ.get("POKESERVER", os.path.join(DEV, "pokeserver"))
WC3 = "Legality/Encounters/Data/Gen3/EncountersWC3.cs"
RSE = "Legality/Encounters/Data/Gen3/Encounters3RSE.cs"
NY = "Legality/Encounters/Templates/Gen3/Gifts/Distribution3NY.cs"
NY_PKL = "Resources/legality/wild/Gen3/encounter_pcny.pkl"
JPN = "Legality/Encounters/Templates/Gen3/Gifts/Distribution3JPN.cs"

LANG = {"Japanese": 1, "English": 2, "French": 3, "Italian": 4, "German": 5, "Spanish": 7}
LANG_FILE = {1: "ja", 3: "fr", 4: "it", 5: "de", 7: "es"}
GAME_ID = {"S": 1, "R": 2, "E": 3, "FR": 4, "LG": 5}
ALL = ["firered", "leafgreen", "ruby", "sapphire", "emerald"]
GAMES = {"R": ALL, "S": ALL, "RS": ALL, "Gen3": ALL, "FRLG": ["firered", "leafgreen"],
         "EFL": ["firered", "leafgreen", "emerald"]}
GENDER = {"Only0": 0, "RandD3_0": 0, "Only1": 1, "RandD3_1": 1, "Recipient": None}
CONSTS = {"PCJPEggTrainerName": "オヤＮＡＭＥ", "M2WishEggOT": ""}
OWNER = {("Encounters3RSE", 251): {"otId": 31121, "secretIdZero": True,
                                     "note": "owner: SID 0; PKHeX leaves the SID unspecified"}}


def read(rel):
    with open(os.path.join(PKHEX, rel), encoding="utf-8-sig") as f:
        return f.read().split("\n")


CATALOG = json.load(open(os.path.join(SERVER, "gifts_catalog.json"), encoding="utf-8"))
INTERNAL = {s["dex"]: s["id"] for s in CATALOG["species"]}
NAME = {s["dex"]: s["name"] for s in CATALOG["species"]}
CHARSET = set(CATALOG["charset"])
SPECIES_TEXT = {}


def species_name(dex, lang):
    if lang not in LANG_FILE:
        return None
    code = LANG_FILE[lang]
    if code not in SPECIES_TEXT:
        path = os.path.join(PKHEX, "Resources/text/other/%s/text_Species_%s.txt" % (code, code))
        SPECIES_TEXT[code] = open(path, encoding="utf-8-sig").read().split("\n")
    name = SPECIES_TEXT[code][dex].strip()
    if lang != 1:
        name = name.upper()
        if not all(ch in CHARSET for ch in name):
            return None
    return name[:10]


def split_top(s):
    out, depth, cur = [], 0, ""
    for ch in s:
        if ch in "([":
            depth += 1
        elif ch in ")]":
            depth -= 1
        if ch == "," and depth == 0:
            out.append(cur.strip())
            cur = ""
        else:
            cur += ch
    if cur.strip():
        out.append(cur.strip())
    return out


def value(v):
    v = v.strip()
    if v.startswith('"'):
        return v.strip('"')
    if v in CONSTS:
        return CONSTS[v]
    if v.startswith("(int)"):
        return LANG[v[5:]]
    if re.match(r"^\d+$", v):
        return int(v, 10)
    return v


def entry(rel, line_no, line):
    m = re.match(r"\s*new\((.*?)\)\s*\{(.*)\},?\s*(//\s*(.*))?$", line)
    if not m:
        return None
    args = split_top(m.group(1))
    props = {}
    for part in split_top(m.group(2)):
        if "=" in part:
            k, v = part.split("=", 1)
            props[k.strip()] = v.strip()
    dex, level, version = int(args[0]), int(args[1]), args[2]
    egg = len(args) > 3 and args[3] == "true"
    met = None
    for a in args[3:]:
        if a.startswith("met:"):
            met = int(a[4:])
        elif re.match(r"^\d+$", a):
            met = int(a)
    moves = []
    if "Moves" in props:
        moves = [int(x) for x in re.findall(r"\d+", props["Moves"])]
    ev = {
        "source": "%s:%d" % (rel, line_no),
        "comment": (m.group(4) or "").strip(),
        "dex": dex, "species": INTERNAL[dex], "level": level, "egg": egg, "version": version,
        "moves": [x for x in moves if x],
        "ot": value(props.get("OriginalTrainerName", '""')),
        "language": value(props["Language"]) if "Language" in props else None,
        "shiny": {"Never": "never", "Always": "always"}.get(props.get("Shiny", "Random"), "random"),
        "fateful": props.get("FatefulEncounter") == "true",
        "nationalRibbon": props.get("RibbonNational") == "true",
        "metLevel": met if met is not None else (0 if egg else level),
    }
    gender = props.get("OriginalTrainerGender")
    ev["otGender"] = GENDER[gender] if gender in GENDER else (None if gender is None else 2)
    if "ID32" in props:
        id32 = int(props["ID32"], 10)
        ev["otId"], ev["secretIdRandom"] = id32, False
    elif "TID16" in props:
        ev["otId"], ev["secretIdRandom"] = int(props["TID16"], 10), True
    return ev


def wc3():
    out, section = [], None
    lines = read(WC3)
    for i, line in enumerate(lines, 1):
        s = re.match(r"\s*private static readonly EncounterGift3\[\] (\w+)", line)
        if s:
            section = s.group(1)
        ev = entry(WC3, i, line)
        if ev:
            ev["group"] = section
            if ev["language"] is None and not ev["egg"]:
                ev["language"] = 2
            if ev["language"] is None and any(ord(ch) > 0x7F for ch in ev["ot"]):
                ev["language"] = 1
            out.append(ev)
    return out


def colo():
    out = []
    lines = read(RSE)
    names = {}
    for line in lines:
        m = re.match(r'\s*private static readonly string\[\] (\w+) = \[(.*)\];', line)
        if m:
            names[m.group(1)] = [x.strip().strip('"') for x in m.group(2).split(",")]
    for i, line in enumerate(lines, 1):
        m = re.match(r"\s*new\((\d+), (\d+), (\w+), (\w+)\)\s*\{(.*)\},?\s*//\s*(.*)$", line)
        if not m or "Bonus" not in "".join(lines[i - 4:i]) or "without" in "".join(lines[i - 4:i]):
            continue
        dex = int(m.group(1))
        props = dict((k.strip(), v.strip()) for k, v in (p.split("=", 1) for p in split_top(m.group(5))))
        ev = {"source": "%s:%d" % (RSE, i), "comment": m.group(6).strip(), "group": "ColoBonus",
              "dex": dex, "species": INTERNAL[dex], "level": int(m.group(2)), "egg": False, "version": m.group(4),
              "moves": [], "ot": names[m.group(3)][1], "language": 1, "shiny": "never", "fateful": False,
              "nationalRibbon": False, "metLevel": int(m.group(2)), "otGender": int(props["OriginalTrainerGender"]),
              "otId": int(props["TID16"]), "secretIdRandom": True}
        fix = OWNER.get(("Encounters3RSE", dex))
        if fix:
            ev["otId"], ev["secretIdRandom"], ev["note"] = fix["otId"], False, fix["note"]
        out.append(ev)
    return out


def pcny():
    lines = read(NY)
    order = []
    enum_at = next(i for i, l in enumerate(lines) if "public enum Distribution3NY" in l)
    for line in lines[enum_at + 2:]:
        m = re.match(r"\s*(\w+),\s*$", line)
        if not m:
            break
        order.append(m.group(1))
    names = {}
    for i, line in enumerate(lines, 1):
        m = re.match(r"\s*(\w+) => (pivot \? (\w) : (\w)|(\w)),", line)
        if m and m.group(1) in order and m.group(1) not in names:
            picks = [m.group(4), m.group(3)] if m.group(3) else [m.group(5)]
            names[m.group(1)] = (["PCNY" + p.lower() for p in picks], i)
    data = open(os.path.join(PKHEX, NY_PKL), "rb").read()
    out = []
    for k in range(len(data) // 12):
        dex, level, dist = struct.unpack_from("<HBB", data, k * 12)
        moves = [x for x in struct.unpack_from("<4H", data, k * 12 + 4) if x]
        dname = order[dist]
        ots, line = names[dname]
        out.append({"source": "%s record %d, %s:%d" % (NY_PKL, k, NY, line), "comment": "PCNY " + dname,
                    "group": "PCNY", "dex": dex, "species": INTERNAL[dex], "level": level, "egg": False,
                    "version": "RS", "moves": moves, "otNames": ots, "language": 2, "shiny": "never",
                    "fateful": False, "nationalRibbon": False, "metLevel": level, "otGender": None,
                    "otIdMax": 2999})
    return out


def pcjp():
    lines = read(JPN)
    text = "\n".join(lines)
    cities = dict(re.findall(r'private const string (\w+) = "(.*?)";', text))
    tids = dict(re.findall(r"(\w+)\s+=> (\d{5}),", text))
    out = []
    for i, line in enumerate(lines, 1):
        m = re.match(r"\s*private static ReadOnlySpan<ushort> Distro(\d) => \[(.*)\];", line)
        if not m:
            continue
        dist = ["First", "Second", "Third", "Fourth", "Fifth", "Sixth"][int(m.group(1)) - 1]
        ots = [cities[c] for c in ["Tokyo", "Yokohama", "Nagoya", "Osaka", "Fukuoka", "Sapporo"]]
        if dist == "Sixth":
            ots = ots[:5]
        for dex in [int(x) for x in m.group(2).split(",")]:
            out.append({"source": "%s:%d" % (JPN, i), "comment": "PCJP " + dist, "group": "PCJP", "dex": dex,
                        "species": INTERNAL[dex], "level": 10, "egg": False, "version": "R", "moves": [],
                        "otNames": ots, "language": 1, "shiny": "never", "fateful": False,
                        "nationalRibbon": False, "metLevel": 10, "otGender": None, "otId": int(tids[dist]),
                        "secretIdRandom": False})
    return out


def slug(text):
    return re.sub(r"[^a-z0-9]+", "_", text.lower()).strip("_")


def main():
    events = wc3() + colo() + pcny() + pcjp()
    seen = {}
    for n, ev in enumerate(events):
        base = "ev%03d_%s" % (n, slug(NAME[ev["dex"]]))
        ev["key"] = base[:28]
        assert ev["key"] not in seen
        seen[ev["key"]] = True
        ev["idNumber"] = 1000 + n
        ev["games"] = GAMES[ev["version"]]
        if ev["version"] in GAME_ID:
            ev["metGame"] = GAME_ID[ev["version"]]
        lang = ev.get("language")
        nick = species_name(ev["dex"], lang) if lang and lang != 2 and not ev["egg"] else None
        if nick:
            ev["nickname"] = nick
        title = NAME[ev["dex"]] if not ev["egg"] else "POKéMON EGG"
        ev["title"] = title
        label = ev["comment"] or title
        ev["label"] = ("%s (%s)" % (label, ev.get("ot") or "/".join(ev.get("otNames", [])) or "recipient"))
    json.dump(events, sys.stdout, ensure_ascii=False, indent=1)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
