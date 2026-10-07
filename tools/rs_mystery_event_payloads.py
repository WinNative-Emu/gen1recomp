#!/usr/bin/env python3
import base64
import json
import os
import shutil
import struct
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
RUBY = os.path.abspath(os.environ.get("POKERUBY", os.path.join(HERE, "..", "..", "pokeruby")))
SOURCE = "data/debug_mystery_event_scripts.s"
BASE = 0x02000000
BOTH_VERSIONS = 0x80 | 0x100

EVENTS = [
    ("rs_eon_ticket", "EON TICKET", "gUnknown_Debug_845DAE1", "gUnknown_Debug_845DAE1End"),
    ("rs_gift_ribbon", "GIFT RIBBON", "gUnknown_Debug_845E3E0", "gUnknown_Debug_845E3E0End"),
]


def tool(name):
    for prefix in ("arm-none-eabi-",):
        path = shutil.which(prefix + name)
        if path:
            return path
    sys.exit("missing arm-none-eabi-" + name)


def crc16(data):
    crc = 0x1121
    for b in data:
        crc ^= b
        for _ in range(8):
            crc = (crc >> 1) ^ 0x8408 if crc & 1 else crc >> 1
    return ~crc & 0xFFFF


def assemble(work):
    preproc = os.path.join(RUBY, "tools", "preproc", "preproc")
    charmap = os.path.join(RUBY, "charmap.txt")
    src = os.path.join(RUBY, SOURCE)
    obj = os.path.join(work, "events.o")
    flags = ["-mcpu=arm7tdmi", "-I", "include", "--defsym", "RUBY=1", "--defsym", "REVISION=0",
             "--defsym", "DEBUG_FIX=0", "--defsym", "ENGLISH=1", "--defsym", "DEBUG=1",
             "--defsym", "MODERN=0"]
    a = subprocess.run([preproc, src, charmap], cwd=RUBY, check=True, capture_output=True).stdout
    b = subprocess.run([tool("cpp"), "-I", "include"], cwd=RUBY, input=a, check=True,
                       capture_output=True).stdout
    c = subprocess.run([preproc, "-ie", src, charmap], cwd=RUBY, input=b, check=True,
                       capture_output=True).stdout
    subprocess.run([tool("as")] + flags + ["-o", obj], cwd=RUBY, input=c, check=True)
    elf = os.path.join(work, "events.elf")
    subprocess.run([tool("ld"), "--section-start", ".rodata=0x%08X" % BASE, "-e", "0", "-o", elf, obj],
                   check=True)
    binary = os.path.join(work, "events.bin")
    subprocess.run([tool("objcopy"), "-O", "binary", "-j", ".rodata", elf, binary], check=True)
    syms = {}
    out = subprocess.run([tool("nm"), elf], check=True, capture_output=True, text=True).stdout
    for line in out.splitlines():
        parts = line.split()
        if len(parts) == 3:
            syms[parts[2]] = int(parts[0], 16)
    with open(binary, "rb") as f:
        return f.read(), syms


def fix_crc(block, start):
    if block[0] != 1 or block[0x11] != 16 or struct.unpack_from("<I", block, 0x12)[0] != 0:
        return
    first = struct.unpack_from("<I", block, 0x16)[0] - start
    last = struct.unpack_from("<I", block, 0x1A)[0] - start
    struct.pack_into("<I", block, 0x12, crc16(block[first:last]))


def main():
    work = tempfile.mkdtemp()
    try:
        image, syms = assemble(work)
    finally:
        shutil.rmtree(work, ignore_errors=True)
    out = []
    for key, title, first, last in EVENTS:
        start, end = syms[first], syms[last]
        block = bytearray(image[start - BASE:end - BASE])
        assert struct.unpack_from("<I", block, 1)[0] == start
        struct.pack_into("<I", block, 13, struct.unpack_from("<I", block, 13)[0] | BOTH_VERSIONS)
        fix_crc(block, start)
        assert 0 < len(block) <= 0x7D4
        out.append({"key": key, "title": title, "payload": base64.b64encode(bytes(block)).decode()})
    json.dump(out, sys.stdout, indent=2)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
