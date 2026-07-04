class_name T
## Moonfair design tokens.
## Source of truth: design/ref/2f_TOKENS.html (Claude Design export, option 1e/2f).

# ---------- color ----------
const BG_NIGHT_DEEP := Color("#171430")   # bg/night_deep
const BG_NIGHT := Color("#1E1B3A")        # bg/night
const BG_DUSK := Color("#2D2A52")         # bg/dusk
const SURFACE_PANEL := Color("#262347")   # surface/panel
const SURFACE_SCRIM := Color(0.0784, 0.0706, 0.1412, 0.85)  # surface/scrim #141224 @85%

const AMBER := Color("#FFB454")           # accent/amber
const GOLD := Color("#FFD98E")            # accent/gold
const CORAL := Color("#FF7E6B")           # accent/coral
const TEAL := Color("#5EEAD4")            # accent/teal
const LAVENDER := Color("#B4A7FF")        # accent/lavender

const TEXT_WARM := Color("#FFF6E6")       # text/warm_white
const TEXT_BODY := Color("#F4F1FF")       # text/body
const TEXT_DIM := Color(0.9569, 0.9451, 1.0, 0.55)  # text/dim #F4F1FF @55%
const TEXT_ON_AMBER := Color("#57330B")   # text/on_amber
const TEXT_ON_TEAL := Color("#0F221E")    # text/on_teal

# Button gradient endpoints (primary pill: #FFC97A -> #FFA13E). StyleBoxFlat is
# flat, so we use the midpoint; real gradient comes with the art pass.
const BTN_AMBER := Color("#FFB55C")
const BTN_AMBER_PRESSED := Color("#F09A3E")

# ---------- shape ----------
const RADIUS_PILL := 999   # buttons, chips
const RADIUS_CARD := 26
const RADIUS_THUMB := 18   # 16-20 in spec
const TOUCH_MIN := 44      # min touch target px

# ---------- type ----------
# display/xl 34/800 · title/card 18/700 · numerals/hud 24/800 (Baloo 2)
# body 14/700 · label/caps 11 +2.4 (Nunito)
const SIZE_DISPLAY_XL := 34
const SIZE_TITLE_CARD := 18
const SIZE_HUD_NUM := 24
const SIZE_BODY := 14
const SIZE_CAPS := 11

const FONT_DISPLAY_PATH := "res://assets/ui/fonts/Baloo2-Bold.ttf"
const FONT_BODY_PATH := "res://assets/ui/fonts/Nunito-Bold.ttf"

static var _display: Font
static var _body: Font

static func display() -> Font:
	if _display == null:
		if ResourceLoader.exists(FONT_DISPLAY_PATH):
			_display = load(FONT_DISPLAY_PATH)
		else:
			_display = ThemeDB.fallback_font
	return _display

static func body() -> Font:
	if _body == null:
		if ResourceLoader.exists(FONT_BODY_PATH):
			_body = load(FONT_BODY_PATH)
		else:
			_body = ThemeDB.fallback_font
	return _body
