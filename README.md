# Moonfair 🌙

A cozy **nightfall wonder-fair** of minigames for Android, built with **Godot 4.3+**.
A magical traveling carnival that only opens after dark — each attraction is a minigame.

## Attractions

| Game | Type | Status |
|---|---|---|
| **Hidden Grove** | Hidden object — endless rounds, find the trinkets before the lanterns dim | ✅ Playable |
| **Lantern Break** | Brick breaker — lantern / ice / crystal bricks | 🔜 Coming soon |
| **Star Threads** | Connect puzzle | 🔜 Coming soon |
| **Clockwork Carousel** | ??? | 🔜 Coming soon |

## Run it

1. Install [Godot 4.3+](https://godotengine.org/download) (standard build, not .NET).
2. Open the project (`project.godot`) in the editor and press **F5**.
3. Desktop mouse clicks emulate touch, so it's fully playable on PC.

## Project layout

```
core/        shared framework — tokens, UI kit, save data, scene routing, overlays
hub/         the fairground menu (arcade hub)
minigames/   one folder per attraction
data/levels/ level definitions (JSON) — item hotspots in 390x820 design space
design/      design source of truth (Claude Design export + extracted refs)
assets/      art, audio, fonts
```

## Design system

The visual identity is defined in `design/ref/` (exported from Claude Design):

- **`2f_TOKENS.html`** — color / type / shape / motion tokens → implemented in [core/tokens.gd](core/tokens.gd)
- `2a`–`2e` — hub, both minigame screens, overlays, UI atoms

Palette: twilight navy base (`#1E1B3A`), lantern amber/gold accents (`#FFB454`/`#FFD98E`),
coral (`#FF7E6B`), moonlit teal (`#5EEAD4`), lavender (`#B4A7FF`).
Type: **Baloo 2** (display + numerals), **Nunito** (UI/body).

### Fonts

Drop these files into `assets/ui/fonts/` (Google Fonts, OFL license):

- `Baloo2-Bold.ttf`
- `Nunito-Bold.ttf`

Until then the engine fallback font is used automatically.

## Hidden Grove content: scene packs

A *scene pack* (`data/scenes/<id>/pack.json`) is a background plus a pool of findable
items. Each round picks a growing subset of the pool (**8 items in round 1, +2 per
round**) and scatters it at random non-overlapping positions in the safe play area —
coordinates are exact by construction and every round is a fresh layout. Timer scales
with item count (`40s + 4s/item`).

Items render as **sprite textures** when the pack provides them, or as drawn glyph
placeholders (`shape` + `color`) until then. The target tray shows the same sprites.

### AI generation pipeline (Gemini)

`tools/generate_scene_pack.py` generates *everything* for a pack:

1. **Background** — busy painted scene (9:16, no items baked in)
2. **Item sprites** — each item generated on white → flood-fill cutout → trimmed
   transparent 256px PNG
3. **pack.json** — updated with all paths

```powershell
$env:GEMINI_API_KEY = "..."
pip install requests pillow
python tools/generate_scene_pack.py grove   # uses existing pack.json item list
python tools/generate_scene_pack.py kitchen --theme "cozy fairground food stall at night" `
    --items "sausage,tomato,cheese,fork,bell,apple,copper pot,kettle,jam jar,mouse"
```

Then open the project in Godot once so it imports the new PNGs.
Because the game composites sprites onto the background at runtime, there is **no
manual hotspot tagging** — the AI never needs to tell us where anything is.

## Testing

```powershell
godot --path D:\www\moonfair                                  # play (mouse = touch)
godot --headless --path D:\www\moonfair res://tests/smoke.tscn  # automated round-to-win test
godot --path D:\www\moonfair --write-movie shots\hub.png --fixed-fps 10 --quit-after 12 --resolution 390x820  # render frames
```

Save file (progress/currency): `%APPDATA%\Godot\app_userdata\Moonfair\moonfair_save.json` — delete to reset.

## Roadmap

- [ ] Generate the grove pack art with Gemini (backgrounds + sprites + hub thumbnails)
- [ ] Audio (music + SFX, wired through settings toggles)
- [ ] More scene packs (kitchen, dock, inn... see Whiteout item lists for inspiration)
- [ ] Lantern Break (brick breaker)
- [ ] Android export (Play Store)
