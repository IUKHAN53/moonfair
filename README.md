# Moonfair 🌙

A cozy **nightfall wonder-fair** of minigames for Android, built with **Godot 4.3+**.
A magical traveling carnival that only opens after dark — each attraction is a minigame.

## Attractions

| Game | Type | Status |
|---|---|---|
| **Hidden Grove** | Hidden object — find the trinkets before the lanterns dim | ✅ Playable |
| **Lantern Break** | Brick breaker — lantern / ice / crystal bricks | 🔜 Next up |
| **Star Threads** | Connect puzzle | Planned |
| **Clockwork Carousel** | ??? | Planned |

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

## Level authoring (hidden object)

Levels are JSON files in `data/levels/`. Items are tap hotspots in **390x820 design
coordinates** with a placeholder `shape`/`color` glyph drawn until real scene art exists:

```json
{ "id": "moon_gem", "name": "moon gem", "shape": "gem", "color": "#8FF5E3", "x": 84, "y": 296, "r": 14 }
```

When AI-generated scene art lands, set `scene_image` to the texture path — items keep the
same coordinates but stop rendering glyphs (the object is *in* the painting).

## Roadmap

- [ ] Lantern Break (brick breaker) — proves the framework handles physics modes
- [ ] Web-based level tagger: drop a scene image → click objects → export level JSON
- [ ] AI scene art pipeline (Gemini) + art-swap in hidden object
- [ ] Audio (music + SFX, wired through settings toggles)
- [ ] More Hidden Grove levels + level select
- [ ] Android export (Play Store)
