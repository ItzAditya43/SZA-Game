extends RefCounted
## Design tokens: the one place colours, spacing and type sizes are defined.
## tools/build_theme.gd turns them into ui/theme/main_theme.tres; custom-drawn
## controls (map, meters, charts) read them directly. Every state colour is also
## paired with a word or icon in the UI, so nothing relies on colour alone.

# Background layers, darkest first.
const BG_APP: Color = Color("121417")
const BG_PANEL: Color = Color("1a1d21")
const BG_CARD: Color = Color("22262b")
const BG_RAISED: Color = Color("2b3036")
const BG_HOVER: Color = Color("343a41")
const BORDER: Color = Color("3a4048")

# Text.
const TEXT: Color = Color("e8e6e1")
const TEXT_MUTED: Color = Color("a3a9b0")
const TEXT_FAINT: Color = Color("6f767e")
const TEXT_ON_ACCENT: Color = Color("16181b")

# States (always shown with a word or icon too).
const OK: Color = Color("5cbf8a")
const WARN: Color = Color("e6aa3c")
const DANGER: Color = Color("ee6a5f")
const INFO: Color = Color("62a8ea")
const ACCENT: Color = Color("f2c14e")

# World colours.
const GROUP: Color = Color("57c7ff")
const INFECTED: Color = Color("e0574f")
const RIVAL: Color = Color("a78bfa")
const WATER: Color = Color("3b82c4")
const NOISE: Color = Color("f2c14e")
const LIGHT: Color = Color("ffd98a")
const SMELL: Color = Color("9bc46a")
const DISEASE: Color = Color("c084fc")

# Spacing scale and type sizes (px at 100% UI scale).
const SPACE_XS: int = 4
const SPACE_S: int = 8
const SPACE_M: int = 12
const SPACE_L: int = 16
const SPACE_XL: int = 24
const SPACE_XXL: int = 32
const FONT_SMALL: int = 13
const FONT_BODY: int = 15
const FONT_H3: int = 17
const FONT_H2: int = 20
const FONT_H1: int = 26
const RADIUS: int = 6

const FONT_NAMES: PackedStringArray = ["Noto Sans", "Inter", "DejaVu Sans", "sans-serif"]


## The colour for a state name: "ok", "warn", "danger", "info", "muted".
static func state_color(state: String) -> Color:
	match state:
		"ok":
			return OK
		"warn":
			return WARN
		"danger":
			return DANGER
		"info":
			return INFO
	return TEXT_MUTED
