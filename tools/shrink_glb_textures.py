#!/usr/bin/env python3
"""Downsize the textures embedded in a .glb.

Meshy exports props with 2048px PBR maps and won't go lower (its texture tool's
floor is 2048), which leaves a handheld prop weighing 30-130 MB — over GitHub's
100 MB hard limit in the worst case. The geometry is never the problem; the
images are. This unpacks the GLB container, resizes every embedded image, and
repacks it, leaving meshes/animations/materials untouched.

    python3 tools/shrink_glb_textures.py in.glb out.glb --max 1024

A GLB is a 12-byte header followed by a JSON chunk and a BIN chunk. Images live
in the BIN, addressed by bufferViews, so the whole buffer is rebuilt with new
offsets after the images change size.
"""
import argparse
import io
import json
import os
import struct
import sys

from PIL import Image

GLB_MAGIC = 0x46546C67
CHUNK_JSON = 0x4E4F534A
CHUNK_BIN = 0x004E4942


def read_glb(path):
    with open(path, "rb") as f:
        data = f.read()
    magic, _version, length = struct.unpack("<III", data[:12])
    if magic != GLB_MAGIC:
        sys.exit("not a .glb file: %s" % path)
    gltf, binary = None, b""
    off = 12
    while off < length:
        clen, ctype = struct.unpack("<II", data[off:off + 8])
        off += 8
        chunk = data[off:off + clen]
        off += clen
        if ctype == CHUNK_JSON:
            gltf = json.loads(chunk.decode("utf-8"))
        elif ctype == CHUNK_BIN:
            binary = chunk
    return gltf, binary


def write_glb(path, gltf, binary):
    js = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    js += b" " * ((4 - len(js) % 4) % 4)          # JSON pads with spaces
    bn = binary + b"\x00" * ((4 - len(binary) % 4) % 4)   # BIN pads with zeros
    total = 12 + 8 + len(js) + 8 + len(bn)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", GLB_MAGIC, 2, total))
        f.write(struct.pack("<II", len(js), CHUNK_JSON))
        f.write(js)
        f.write(struct.pack("<II", len(bn), CHUNK_BIN))
        f.write(bn)


def shrink_image(raw, max_px, quality):
    img = Image.open(io.BytesIO(raw))
    before = img.size
    if max(img.size) > max_px:
        scale = max_px / float(max(img.size))
        img = img.resize((max(1, int(img.width * scale)),
                          max(1, int(img.height * scale))), Image.LANCZOS)
    # Keep PNG only when the alpha channel is actually carrying something;
    # everything else re-encodes to JPEG, which is most of the saving.
    has_alpha = img.mode in ("RGBA", "LA") and img.getchannel("A").getextrema()[0] < 255
    out = io.BytesIO()
    if has_alpha:
        img.convert("RGBA").save(out, format="PNG", optimize=True)
        mime = "image/png"
    else:
        img.convert("RGB").save(out, format="JPEG", quality=quality, optimize=True)
        mime = "image/jpeg"
    return out.getvalue(), mime, before, img.size


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--max", type=int, default=1024, help="longest edge, px")
    ap.add_argument("--quality", type=int, default=88, help="JPEG quality")
    args = ap.parse_args()

    gltf, binary = read_glb(args.src)
    images = gltf.get("images", [])
    views = gltf.get("bufferViews", [])
    if not images:
        sys.exit("no embedded images in %s" % args.src)

    replaced = {}
    for i, img in enumerate(images):
        if "bufferView" not in img:
            print("  image %d: external/data URI, skipped" % i)
            continue
        vi = img["bufferView"]
        v = views[vi]
        start = v.get("byteOffset", 0)
        raw = binary[start:start + v["byteLength"]]
        new, mime, before, after = shrink_image(raw, args.max, args.quality)
        print("  image %d: %dx%d -> %dx%d   %.1f MB -> %.2f MB"
              % (i, before[0], before[1], after[0], after[1],
                 len(raw) / 1048576.0, len(new) / 1048576.0))
        replaced[vi] = new
        img["mimeType"] = mime

    # Rebuild the whole binary chunk so every bufferView gets a fresh offset.
    out = bytearray()
    for i, v in enumerate(views):
        data = replaced.get(i)
        if data is None:
            start = v.get("byteOffset", 0)
            data = binary[start:start + v["byteLength"]]
        out += b"\x00" * ((4 - len(out) % 4) % 4)   # keep views 4-byte aligned
        v["byteOffset"] = len(out)
        v["byteLength"] = len(data)
        out += data
    gltf["buffers"][0]["byteLength"] = len(out)
    if "uri" in gltf["buffers"][0]:
        del gltf["buffers"][0]["uri"]

    write_glb(args.dst, gltf, bytes(out))
    a = os.path.getsize(args.src) / 1048576.0
    b = os.path.getsize(args.dst) / 1048576.0
    print("%s  %.1f MB  ->  %s  %.1f MB  (%.0f%% smaller)"
          % (args.src, a, args.dst, b, (1 - b / a) * 100))


if __name__ == "__main__":
    main()
