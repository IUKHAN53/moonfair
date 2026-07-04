#!/usr/bin/env python3
"""Generate a Moonfair hidden-object scene pack with Gemini image generation.

Approach (baked items):
  1. Generate a realistic base scene (no findable items in it).
  2. For each item, WE pick the exact position, crop a patch around it, and ask
     Gemini's image editor to paint the item into that patch — small, blended,
     partially hidden. The edited patch is pasted back with a feathered mask.
  3. Gemini vision verifies the item is actually visible in the patch
     (retry once with a stronger prompt; drop the item if it still fails).
  4. pack.json gets each item's exact image-pixel coordinates.

The game shows the finished image full-bleed, players get NAMES only, and taps
are hit-tested against the stored coordinates. Same scene serves all 12 stages
of a chapter (each stage asks for a random subset of the pool).

Usage:
  # .env in project root with GEMINI_API_KEY=... (or env var)
  python tools/generate_scene_pack.py jungle \
      --theme "lush tropical jungle with a river, dense foliage, mist" \
      --items "parrot,butterfly,mushroom,tree frog,snail,orchid,banana,nest"

Options:
  --theme       scene description (default derived from pack id)
  --items       comma-separated item names (else read from existing pack.json)
  --bg-only     only generate the base scene
  --force       regenerate everything (default: skip existing bg / placed items)
  --no-verify   skip the vision verification pass
  --patch N     edit patch size in px (default 280)
  --seed N      reproducible item placement

Requires: pip install requests pillow
"""

import argparse
import base64
import io
import json
import math
import os
import random
import sys
import time
from pathlib import Path

import requests
from PIL import Image, ImageDraw, ImageFilter

IMAGE_MODEL = "gemini-2.5-flash-image"
VISION_MODEL = "gemini-2.5-flash"
API = "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"

ROOT = Path(__file__).resolve().parent.parent
SCENES = ROOT / "data" / "scenes"

STYLE = ("highly detailed realistic digital painting, natural colors, "
         "soft natural light, rich texture, no text, no watermark")

BG_PROMPT = (
    "A {theme}, {style}. Tall portrait composition, busy and layered with "
    "natural detail everywhere — foreground, midground and background all "
    "interesting. No people. No single object given prominence; this is a "
    "background for a hidden-object game, so it needs many natural nooks, "
    "shadows and textures where small things could hide."
)

HIDE_PROMPT = (
    "Edit this image patch for a hidden-object game: add exactly ONE small "
    "{item}, roughly centered. It must blend naturally into the scene — "
    "correct scale, matching light and painting style, partially tucked "
    "behind/among existing elements so it is subtle but clearly recognizable "
    "when you look directly at it. Do NOT change anything else in the patch. "
    "Keep the exact same art style and colors."
)

HIDE_PROMPT_STRONG = (
    "Edit this image patch: paint exactly ONE small but clearly visible "
    "{item} in the CENTER of the patch. Match the painting style and "
    "lighting. It should look like it belongs in the scene, but a player "
    "must be able to recognize it. Change nothing else."
)

VERIFY_PROMPT = (
    "Look at this image patch from a hidden-object game. Is there a "
    "recognizable {item} at or near the center? A player must be able to "
    "spot it when looking carefully. Answer with exactly one word: YES or NO."
)


# ---------- api ----------

def _load_dotenv() -> None:
    env_file = ROOT / ".env"
    if not env_file.exists():
        return
    for line in env_file.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, _, v = line.partition("=")
        os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))


def api_key() -> str:
    _load_dotenv()
    key = os.environ.get("GEMINI_API_KEY", "")
    if not key:
        sys.exit("GEMINI_API_KEY is not set (env var or .env in project root)")
    return key


def _call(model: str, parts: list, gen_config: dict | None = None,
          retries: int = 4) -> dict:
    body = {"contents": [{"parts": parts}]}
    if gen_config:
        body["generationConfig"] = gen_config
    for attempt in range(retries):
        r = requests.post(API.format(model=model), params={"key": api_key()},
                          json=body, timeout=180)
        if r.status_code in (429, 500, 503):
            wait = 12 * (attempt + 1)
            print(f"    {r.status_code}, retrying in {wait}s...")
            time.sleep(wait)
            continue
        r.raise_for_status()
        return r.json()
    raise RuntimeError(f"gave up after {retries} retries")


def _img_part(img: Image.Image) -> dict:
    buf = io.BytesIO()
    img.convert("RGB").save(buf, "PNG")
    return {"inline_data": {"mime_type": "image/png",
                            "data": base64.b64encode(buf.getvalue()).decode()}}


def gen_image(prompt: str, aspect: str = "1:1",
              base: Image.Image | None = None) -> Image.Image:
    parts = [{"text": prompt}]
    if base is not None:
        parts.append(_img_part(base))
    cfg = {"responseModalities": ["IMAGE"]}
    if base is None:
        cfg["imageConfig"] = {"aspectRatio": aspect}
    data = _call(IMAGE_MODEL, parts, cfg)
    for part in data["candidates"][0]["content"]["parts"]:
        inline = part.get("inlineData") or part.get("inline_data")
        if inline:
            raw = base64.b64decode(inline["data"])
            return Image.open(io.BytesIO(raw)).convert("RGB")
    raise RuntimeError(f"no image in response: {json.dumps(data)[:300]}")


def verify_item(patch: Image.Image, item: str) -> bool:
    data = _call(VISION_MODEL,
                 [{"text": VERIFY_PROMPT.format(item=item)}, _img_part(patch)])
    try:
        text = data["candidates"][0]["content"]["parts"][0]["text"]
    except (KeyError, IndexError):
        return False
    return "YES" in text.upper()


# ---------- placement ----------

def pick_positions(n: int, w: int, h: int, patch: int, rng: random.Random,
                   occupied: list | None = None) -> list:
    """Non-overlapping item centers, clear of HUD (top), tray (bottom) and the
    side crop the game's cover-fit may apply on narrow screens.

    Capacity-aware: starts at the ideal spacing and relaxes it in steps if the
    field can't fit n items, down to a hard floor where overlapping edit
    patches would start erasing earlier items. Items that still don't fit are
    dropped (returned as None) rather than clustered.

    `occupied` = centers of already-baked items (exclusion zones for re-runs).
    """
    x_lo, x_hi = int(w * 0.16), int(w * 0.84)
    y_lo, y_hi = int(h * 0.13), int(h * 0.76)
    taken = list(occupied or [])
    floor = patch * 0.55  # below this, patch overlap starts eating neighbours
    min_dist = patch * 0.9
    while min_dist >= floor:
        out: list = []
        ok = True
        for _ in range(n):
            for _attempt in range(500):
                p = (rng.randint(x_lo, x_hi), rng.randint(y_lo, y_hi))
                if all(math.dist(p, q) >= min_dist for q in out + taken):
                    out.append(p)
                    break
            else:
                ok = False
                break
        if ok:
            return out
        min_dist *= 0.9
    # even the floor spacing can't fit everything: place what fits, drop the rest
    out = []
    for _ in range(n):
        placed = None
        for _attempt in range(500):
            p = (rng.randint(x_lo, x_hi), rng.randint(y_lo, y_hi))
            if all(math.dist(p, q) >= floor for q in out + taken):
                placed = p
                break
        out.append(placed)  # None = drop this item
    return out


def feather_mask(size: int, solid: float = 0.55) -> Image.Image:
    """Radial mask: opaque center, feathered edges — hides paste seams."""
    m = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(m)
    d.ellipse([size * (1 - solid) / 2, size * (1 - solid) / 2,
               size * (1 + solid) / 2, size * (1 + solid) / 2], fill=255)
    return m.filter(ImageFilter.GaussianBlur(size * (1 - solid) / 3))


# ---------- main ----------

def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("pack_id")
    ap.add_argument("--theme", default="")
    ap.add_argument("--items", default="")
    ap.add_argument("--bg-only", action="store_true")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--no-verify", action="store_true")
    ap.add_argument("--patch", type=int, default=280)
    ap.add_argument("--seed", type=int, default=None)
    args = ap.parse_args()

    rng = random.Random(args.seed)
    pack_dir = SCENES / args.pack_id
    pack_dir.mkdir(parents=True, exist_ok=True)
    pack_path = pack_dir / "pack.json"
    bg_path = pack_dir / "bg.png"

    pack = (json.loads(pack_path.read_text(encoding="utf-8"))
            if pack_path.exists() else
            {"id": args.pack_id, "name": args.pack_id.replace("_", " ").title(),
             "background": "", "items": []})

    def slug(name: str) -> str:
        import re
        return re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")

    if args.items:
        names = [n.strip() for n in args.items.split(",") if n.strip()]
        existing = {it["id"] for it in pack["items"]}
        for n in names:
            if slug(n) not in existing:
                pack["items"].append({"id": slug(n), "name": n})
    if not pack["items"]:
        sys.exit("no items: pass --items or add them to pack.json first")

    theme = args.theme or f"beautiful natural {args.pack_id.replace('_', ' ')} landscape"

    # ---- base scene ----
    if bg_path.exists() and not args.force:
        print(f"bg: exists, keeping ({bg_path})")
        scene = Image.open(bg_path).convert("RGB")
    else:
        print(f"bg: generating '{theme}' ...")
        scene = gen_image(BG_PROMPT.format(theme=theme, style=STYLE), aspect="9:16")
        scene.save(bg_path, "PNG")
        print(f"bg: saved {bg_path} ({scene.size[0]}x{scene.size[1]})")
        # base changed: all previously baked coordinates are stale
        for it in pack["items"]:
            it.pop("x", None)
            it.pop("y", None)
            it.pop("r", None)
    pack["background"] = f"res://data/scenes/{args.pack_id}/bg.png"

    if args.bg_only:
        pack_path.write_text(json.dumps(pack, indent="\t", ensure_ascii=False) + "\n",
                             encoding="utf-8")
        print("bg-only: done")
        return

    # ---- hide items into the scene ----
    w, h = scene.size
    patch_sz = args.patch
    todo = [it for it in pack["items"] if args.force or "x" not in it]
    occupied = [(it["x"], it["y"]) for it in pack["items"]
                if "x" in it and it not in todo]
    print(f"hiding {len(todo)} items (patch {patch_sz}px, verify={'off' if args.no_verify else 'on'})")
    positions = pick_positions(len(todo), w, h, patch_sz, rng, occupied)
    mask = feather_mask(patch_sz)
    dropped = []

    for it, pos in zip(todo, positions):
        if pos is None:
            print(f"  {it['name']}: no room left in the scene, dropping")
            dropped.append(it["name"])
            it.pop("x", None)
            continue
        cx, cy = pos
        x0 = max(0, min(w - patch_sz, cx - patch_sz // 2))
        y0 = max(0, min(h - patch_sz, cy - patch_sz // 2))
        box = (x0, y0, x0 + patch_sz, y0 + patch_sz)
        placed = False
        for round_i, prompt in enumerate((HIDE_PROMPT, HIDE_PROMPT_STRONG)):
            print(f"  {it['name']}: hiding at ({cx},{cy})"
                  + (" [retry]" if round_i else ""))
            patch = scene.crop(box)
            edited = gen_image(prompt.format(item=it["name"]), base=patch)
            if edited.size != (patch_sz, patch_sz):
                edited = edited.resize((patch_sz, patch_sz), Image.LANCZOS)
            if args.no_verify or verify_item(edited, it["name"]):
                scene.paste(edited, (x0, y0), mask)
                it["x"] = x0 + patch_sz // 2
                it["y"] = y0 + patch_sz // 2
                it["r"] = int(patch_sz * 0.32)
                placed = True
                break
            print(f"  {it['name']}: verify said NO")
        if not placed:
            dropped.append(it["name"])
            it.pop("x", None)

    scene.save(bg_path, "PNG")

    # ---- final verification against the finished composite ----
    # catches items a later overlapping patch painted over
    if not args.no_verify:
        print("final verify pass on the composed scene...")
        for it in pack["items"]:
            if "x" not in it:
                continue
            r = patch_sz // 2
            box = (max(0, it["x"] - r), max(0, it["y"] - r),
                   min(w, it["x"] + r), min(h, it["y"] + r))
            if not verify_item(scene.crop(box), it["name"]):
                print(f"  {it['name']}: MISSING from final image, dropping")
                dropped.append(it["name"])
                it.pop("x", None)

    pack_path.write_text(json.dumps(pack, indent="\t", ensure_ascii=False) + "\n",
                         encoding="utf-8")
    ok = sum(1 for it in pack["items"] if "x" in it)
    print(f"done: {ok}/{len(pack['items'])} items baked into {bg_path}")
    if dropped:
        print(f"dropped (excluded from play): {', '.join(dropped)}")
    print("Re-run the same command to retry dropped items at fresh positions.")
    print("Open the project in Godot once so it re-imports bg.png.")


if __name__ == "__main__":
    main()
