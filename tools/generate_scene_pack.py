#!/usr/bin/env python3
"""Generate a Moonfair hidden-object scene pack with Gemini image generation.

Approach (layered patches):
  1. Generate a clean stylized base scene (bg.png — no findable items in it).
  2. For each item, WE pick the exact position, crop a patch around it, and ask
     Gemini's image editor to paint the item into that patch. The edited patch
     is saved as its own PNG with a feathered alpha edge (patches/<id>.png).
  3. Gemini vision verifies the item is actually visible in the patch
     (retry once with a stronger prompt; drop the item if it still fails).
  4. pack.json gets each item's patch path + exact image-pixel coordinates.

The game layers unfound items' patches over the base at runtime, so a found
item VISIBLY DISAPPEARS from the scene. Players get NAMES only (3 active
targets at a time), and taps are hit-tested against the stored coordinates.
Same scene serves all 12 stages of a chapter.

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
from PIL import Image, ImageChops, ImageDraw, ImageFilter

IMAGE_MODEL = "gemini-2.5-flash-image"
VISION_MODEL = "gemini-2.5-flash"
API = "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"

ROOT = Path(__file__).resolve().parent.parent
SCENES = ROOT / "data" / "scenes"

STYLE = ("bright cheerful stylized 3D cartoon game art, clean bold shapes, "
         "vivid saturated colors, soft sunny daylight, crisp and readable, "
         "like a modern casual mobile city-builder game, no text, no watermark")

BG_PROMPT = (
    "A {theme}, {style}. Tall portrait composition. A cozy, inviting game "
    "scene with many DISTINCT props, surfaces, shelves and corners — "
    "readable and evenly lit, never murky or cluttered. No people. No single "
    "object given prominence; this is a background for a hidden-object game, "
    "so it needs plenty of clean surfaces and nooks where small objects "
    "could sit naturally."
)

HIDE_PROMPT = (
    "Edit this image patch for a hidden-object game: add exactly ONE small "
    "stylized {item}, roughly centered, placed naturally on or against the "
    "existing surfaces. It must be clearly recognizable at a glance and "
    "match the bright cartoon art style and lighting exactly. Do NOT change "
    "anything else in the patch."
)

HIDE_PROMPT_STRONG = (
    "Edit this image patch: add exactly ONE small cute cartoon {item} in "
    "the CENTER of the patch, clearly visible and instantly recognizable. "
    "Match the bright stylized art style and lighting. Change nothing else."
)

REMOVE_PROMPT = (
    "Edit this image patch: completely REMOVE the {item} and seamlessly fill "
    "the area with whatever is behind/around it (wall, ground, foliage, "
    "water...). The fill must be smooth and clean — no smudges, no brush "
    "marks, no blur. Do not add any new object. Change nothing else in the "
    "patch. Keep the exact same art style, colors and lighting."
)

VERIFY_PROMPT = (
    "Look at this image patch from a hidden-object game. Is there a "
    "recognizable {item} at or near the center? A player must be able to "
    "spot it when looking carefully. Answer with exactly one word: YES or NO."
)

LOCATE_PROMPT = (
    "Find the {item} in this image. Return ONLY JSON, no prose: "
    '{{"box_2d": [ymin, xmin, ymax, xmax]}} with coordinates normalized to '
    "0-1000 and the box TIGHT around the {item} only."
)

DETECT_PROMPT = (
    "You are labeling a scene for a hidden-object game (like the classic "
    "seek-and-find genre). Identify up to {n} DISTINCT, clearly visible, "
    "concrete objects in this image that a player could be asked to find by "
    "name. Prefer small-to-medium props: tools, containers, plants, fruit, "
    "animals, decorations, architectural details (a barrel, a rope bridge, a "
    "lantern, a log...). Do NOT include broad regions (sky, water, ground, "
    "grass, generic trees or rocks), people, or two entries for the same "
    "object. Each name must be unique. Return ONLY a JSON array where each "
    'element is {{"label": "<short object name>", "box_2d": [ymin, xmin, '
    "ymax, xmax]}} with coordinates normalized to 0-1000, boxes tight around "
    "the object."
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
    candidates = data.get("candidates") or []
    if not candidates or "content" not in candidates[0]:
        reason = candidates[0].get("finishReason", "?") if candidates else "no candidates"
        raise RuntimeError(f"generation returned no content ({reason})")
    for part in candidates[0]["content"].get("parts", []):
        inline = part.get("inlineData") or part.get("inline_data")
        if inline:
            raw = base64.b64decode(inline["data"])
            return Image.open(io.BytesIO(raw)).convert("RGB")
    raise RuntimeError(f"no image in response: {json.dumps(data)[:300]}")


def slug(name: str) -> str:
    import re
    return re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")


def detect_native_items(scene: Image.Image, taken_ids: set, max_n: int = 25) -> list:
    """Ask Gemini vision to label objects ALREADY in the base scene.

    These become findable items for free — the Whiteout way, where most
    findables (barrel, ladder, bench...) are part of the scene art itself.
    """
    data = _call(VISION_MODEL,
                 [{"text": DETECT_PROMPT.format(n=max_n)}, _img_part(scene)])
    try:
        text = data["candidates"][0]["content"]["parts"][0]["text"].strip()
    except (KeyError, IndexError):
        return []
    if text.startswith("```"):
        text = text.strip("`")
        if text.startswith("json"):
            text = text[4:]
    try:
        arr = json.loads(text)
    except json.JSONDecodeError:
        print("  detect: could not parse response, skipping natives")
        return []
    w, h = scene.size
    out: list = []
    for e in arr:
        try:
            y0, x0, y1, x1 = [int(v) for v in e["box_2d"]]
            name = str(e["label"]).strip().lower()
        except (KeyError, TypeError, ValueError):
            continue
        bx, by = int(x0 / 1000 * w), int(y0 / 1000 * h)
        bw, bh = int((x1 - x0) / 1000 * w), int((y1 - y0) / 1000 * h)
        if bw <= 0 or bh <= 0 or not name:
            continue
        area = (bw * bh) / (w * h)
        if area < 0.001 or area > 0.12:   # too tiny to tap / too huge to be fair
            continue
        cx, cy = bx + bw // 2, by + bh // 2
        # keep clear of the HUD strip, the tray, and the cover-crop side margins
        if not (0.06 * w < cx < 0.94 * w and 0.09 * h < cy < 0.78 * h):
            continue
        sid = slug(name)
        if sid in taken_ids:
            continue
        # skip if the center sits inside an already-accepted native box
        if any(n["bx"] <= cx <= n["bx"] + n["bw"] and n["by"] <= cy <= n["by"] + n["bh"]
               for n in out):
            continue
        taken_ids.add(sid)
        out.append({"id": sid, "name": name, "kind": "native",
                    "bx": bx, "by": by, "bw": bw, "bh": bh, "x": cx, "y": cy})
        if len(out) >= max_n:
            break
    return out


def locate_in_patch(patch: Image.Image, item: str):
    """Tight bounding box of the item inside its patch (px), or None."""
    data = _call(VISION_MODEL,
                 [{"text": LOCATE_PROMPT.format(item=item)}, _img_part(patch)])
    try:
        text = data["candidates"][0]["content"]["parts"][0]["text"].strip()
    except (KeyError, IndexError):
        return None
    if text.startswith("```"):
        text = text.strip("`")
        if text.startswith("json"):
            text = text[4:]
    try:
        y0, x0, y1, x1 = [int(v) for v in json.loads(text)["box_2d"]]
    except (json.JSONDecodeError, KeyError, TypeError, ValueError):
        return None
    ps = patch.size[0]
    bx, by = int(x0 / 1000 * ps), int(y0 / 1000 * ps)
    bw, bh = int((x1 - x0) / 1000 * ps), int((y1 - y0) / 1000 * ps)
    if bw < 12 or bh < 12 or bw > ps * 0.95 or bh > ps * 0.95:
        return None
    return (bx, by, bw, bh)


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
    placed_pts: list = []
    for _ in range(n):
        placed = None
        for _attempt in range(500):
            p = (rng.randint(x_lo, x_hi), rng.randint(y_lo, y_hi))
            if all(math.dist(p, q) >= floor for q in placed_pts + taken):
                placed = p
                break
        out.append(placed)  # None = drop this item
        if placed is not None:
            placed_pts.append(placed)
    return out


def region_diff(a: Image.Image, b: Image.Image) -> float:
    """Mean absolute RGB difference (0-255) between two same-size crops."""
    import itertools
    a = a.convert("RGB")
    b = b.convert("RGB")
    if a.size != b.size or a.size[0] == 0 or a.size[1] == 0:
        return 255.0
    pa, pb = a.tobytes(), b.tobytes()
    return sum(abs(x - y) for x, y in zip(pa, pb)) / len(pa)


def feather_mask(size: int, solid: float = 0.55) -> Image.Image:
    """Rounded-square mask: opaque center, feathered edges — hides paste seams
    while keeping the whole object bounds fully opaque."""
    m = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(m)
    off = size * (1 - solid) / 2
    d.rounded_rectangle([off, off, size - off, size - off],
                        radius=size * 0.1, fill=255)
    return m.filter(ImageFilter.GaussianBlur(size * (1 - solid) / 3.5))


def diff_alpha(orig: Image.Image, edited: Image.Image, bbox=None,
               threshold: int = 18) -> Image.Image:
    """Overlay alpha from the actual pixel difference: only where the edit
    changed the image stays opaque, so the overlay carries exactly the object —
    no tint squares, no ghost edges. Optional bbox (patch-local x,y,w,h) gates
    out stray changes far from the object."""
    diff = ImageChops.difference(orig.convert("RGB"), edited.convert("RGB")).convert("L")
    mask = diff.point(lambda v: 255 if v > threshold else 0)
    mask = mask.filter(ImageFilter.MaxFilter(11))
    if bbox:
        ps = orig.size[0]
        gate = Image.new("L", (ps, ps), 0)
        d = ImageDraw.Draw(gate)
        pad = 20
        d.rounded_rectangle([max(0, bbox[0] - pad), max(0, bbox[1] - pad),
                             min(ps, bbox[0] + bbox[2] + pad),
                             min(ps, bbox[1] + bbox[3] + pad)],
                            radius=14, fill=255)
        gate = gate.filter(ImageFilter.GaussianBlur(4))
        mask = ImageChops.multiply(mask, gate)
    return mask.filter(ImageFilter.GaussianBlur(3))


# ---------- main ----------

def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("pack_id")
    ap.add_argument("--theme", default="")
    ap.add_argument("--items", default="")
    ap.add_argument("--bg-only", action="store_true")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--no-verify", action="store_true")
    ap.add_argument("--no-detect", action="store_true",
                    help="skip detecting native scene objects as findables")
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

    def save_pack() -> None:
        # crash-safe: persist after every phase so a failure never orphans
        # already-generated overlays
        pack_path.write_text(json.dumps(pack, indent="\t", ensure_ascii=False) + "\n",
                             encoding="utf-8")

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
        # base changed: previously generated patches and detected natives are stale
        pack["items"] = [it for it in pack["items"] if it.get("kind") != "native"]
        for it in pack["items"]:
            for k in ("x", "y", "r", "patch", "px", "py", "ps", "bx", "by", "bw", "bh"):
                it.pop(k, None)
        # and their overlay PNGs must not survive to be mistaken for current art
        stale_dir = pack_dir / "patches"
        if stale_dir.exists():
            for f in stale_dir.glob("*.png"):
                f.unlink()
        save_pack()
    pack["background"] = f"res://data/scenes/{args.pack_id}/bg.png"

    # ---- harvest objects already painted into the scene (the Whiteout way) ----
    if not args.no_detect and not any(it.get("kind") == "native" for it in pack["items"]):
        print("detecting native scene objects...")
        taken = {it["id"] for it in pack["items"]}
        natives = detect_native_items(scene, taken)
        pack["items"].extend(natives)
        print(f"  +{len(natives)} natives: " + ", ".join(n["name"] for n in natives))
        save_pack()

    if args.bg_only:
        pack_path.write_text(json.dumps(pack, indent="\t", ensure_ascii=False) + "\n",
                             encoding="utf-8")
        print("bg-only: done")
        return

    patches_dir = pack_dir / "patches"
    patches_dir.mkdir(exist_ok=True)
    w, h = scene.size

    # ---- lift native objects into removable layers ----
    # Whiteout-style: even a pipe on the wall pops off when found. The object
    # is REMOVED from the base (inpainted) and its original pixels become the
    # item's overlay layer — identical look, but it can vanish.
    natives_todo = [it for it in pack["items"]
                    if it.get("kind") == "native" and "patch" not in it and it.get("bw")]
    if natives_todo:
        print(f"lifting {len(natives_todo)} native objects into removable layers")
        base_dirty = False
        for it in natives_todo:
            nb_w, nb_h = int(it["bw"]), int(it["bh"])
            # only small discrete objects can plausibly "pop off" the scene —
            # inpainting away a church/tree/waterfall scars the base
            if max(nb_w, nb_h) > 200 or (nb_w * nb_h) > 0.04 * w * h:
                print(f"  {it['name']}: too large to lift — stays scenery, not findable")
                continue
            ps = int(min(max(max(nb_w, nb_h) * 1.7, 170), 340))
            ps = min(ps, w, h)
            x0 = max(0, min(w - ps, int(it["x"]) - ps // 2))
            y0 = max(0, min(h - ps, int(it["y"]) - ps // 2))
            orig = scene.crop((x0, y0, x0 + ps, y0 + ps))
            # object bbox in patch-local coords, for the pixel-diff guard
            rb = (max(0, int(it["bx"]) - x0), max(0, int(it["by"]) - y0))
            rbox = (rb[0], rb[1], min(ps, rb[0] + nb_w), min(ps, rb[1] + nb_h))
            removed = False
            for round_i in range(2):
                print(f"  {it['name']}: removing from base" + (" [retry]" if round_i else ""))
                try:
                    cleaned = gen_image(REMOVE_PROMPT.format(item=it["name"]), base=orig)
                except RuntimeError as e:
                    print(f"  {it['name']}: {e}")
                    continue
                if cleaned.size != (ps, ps):
                    cleaned = cleaned.resize((ps, ps), Image.LANCZOS)
                # deterministic guard: the object's pixels must actually change —
                # vision verify alone sometimes waves through a no-op edit
                d = region_diff(orig.crop(rbox), cleaned.crop(rbox))
                if d < 8.0:
                    print(f"  {it['name']}: edit barely changed the region (diff {d:.1f})")
                    continue
                if args.no_verify or not verify_item(cleaned, it["name"]):
                    removed = True
                    break
            if not removed:
                print(f"  {it['name']}: could not remove cleanly — stays scenery, not findable")
                continue
            # base gets the cleaned region (solid over the object, feathered out)
            solid = min(0.88, max(nb_w, nb_h) / ps + 0.2)
            scene.paste(cleaned, (x0, y0), feather_mask(ps, solid))
            base_dirty = True
            # overlay carries ONLY the object pixels: alpha from the removal diff
            rgba = orig.convert("RGBA")
            rgba.putalpha(diff_alpha(orig, cleaned, (rbox[0], rbox[1], nb_w, nb_h)))
            rgba.save(patches_dir / f"{it['id']}.png", "PNG")
            it["patch"] = f"res://data/scenes/{args.pack_id}/patches/{it['id']}.png"
            it["px"] = x0
            it["py"] = y0
            it["ps"] = ps
            scene.save(bg_path, "PNG")
            save_pack()
        if base_dirty:
            scene.save(bg_path, "PNG")

    # ---- generate planted item patches (layered over the base at runtime) ----
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
            try:
                edited = gen_image(prompt.format(item=it["name"]), base=patch)
            except RuntimeError as e:
                print(f"  {it['name']}: {e}")
                continue
            if edited.size != (patch_sz, patch_sz):
                edited = edited.resize((patch_sz, patch_sz), Image.LANCZOS)
            if args.no_verify or verify_item(edited, it["name"]):
                it["patch"] = f"res://data/scenes/{args.pack_id}/patches/{it['id']}.png"
                it["px"] = x0
                it["py"] = y0
                it["ps"] = patch_sz
                it["x"] = x0 + patch_sz // 2
                it["y"] = y0 + patch_sz // 2
                it["r"] = int(patch_sz * 0.32)
                # tight hit box, sized to the item itself
                loc = None if args.no_verify else locate_in_patch(edited, it["name"])
                if loc:
                    it["bx"] = x0 + loc[0]
                    it["by"] = y0 + loc[1]
                    it["bw"] = loc[2]
                    it["bh"] = loc[3]
                    it["x"] = it["bx"] + loc[2] // 2
                    it["y"] = it["by"] + loc[3] // 2
                # overlay carries ONLY the added object: alpha from the edit diff
                rgba = edited.convert("RGBA")
                rgba.putalpha(diff_alpha(patch, edited, loc))
                rgba.save(patches_dir / f"{it['id']}.png", "PNG")
                placed = True
                break
            print(f"  {it['name']}: verify said NO")
        if not placed:
            dropped.append(it["name"])
            it.pop("x", None)
        save_pack()

    pack_path.write_text(json.dumps(pack, indent="\t", ensure_ascii=False) + "\n",
                         encoding="utf-8")
    ok = sum(1 for it in pack["items"] if "x" in it)
    print(f"done: {ok}/{len(pack['items'])} item patches in {patches_dir}")
    if dropped:
        print(f"dropped (excluded from play): {', '.join(dropped)}")
    print("Re-run the same command to retry dropped items at fresh positions.")
    print("Open the project in Godot once so it imports the new PNGs.")


if __name__ == "__main__":
    main()
