#!/usr/bin/env python3
import argparse
import struct
import subprocess
import zlib

ap = argparse.ArgumentParser()
ap.add_argument("--src", default="assets/launcher/current_theme_vid.ogv")
ap.add_argument("--dst", default="assets/launcher/current_theme_sheet.bin")
ap.add_argument("--width", type=int, default=640)
ap.add_argument("--fps", type=int, default=12)
ap.add_argument("--max-texture", type=int, default=4096)
args = ap.parse_args()

W = args.width
H = round(W * 902 / 1280 / 2) * 2
raw = subprocess.run(
    ["ffmpeg", "-v", "error", "-i", args.src,
     "-vf", f"fps={args.fps},scale={W}:{H}", "-pix_fmt", "gray", "-f", "rawvideo", "-"],
    check=True, stdout=subprocess.PIPE).stdout
size = W * H
frames = len(raw) // size
cols = args.max_texture // W
rows = args.max_texture // H
per = cols * rows
sheets = -(-frames // per)
stride = cols * W
out = bytearray()
for s in range(sheets):
    sheet = bytearray(stride * rows * H)
    for slot in range(per):
        i = s * per + slot
        if i >= frames:
            break
        fx, fy = (slot % cols) * W, (slot // cols) * H
        for y in range(H):
            src = i * size + y * W
            dst = (fy + y) * stride + fx
            sheet[dst:dst + W] = raw[src:src + W]
    out += sheet

header = struct.pack("<7H", W, H, cols, rows, frames, args.fps, sheets)
with open(args.dst, "wb") as f:
    f.write(zlib.compress(header + bytes(out), 9))
print(f"{args.dst}: {W}x{H}, {frames} frames, {sheets} sheets of {stride}x{rows * H}")
