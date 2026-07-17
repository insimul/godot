class_name InsimulUiTokens
extends RefCounted
## Shared UI design tokens + Godot Theme builder (US-GU1).
##
## These constants are the Godot mirror of the engine-neutral token set in
## packages/core/conformance/ui/theme-tokens.json — the single source of truth
## every default-UI mirror (Babylon CSS vars, Unity UIStyleSheet, Unreal Slate,
## Godot Theme) maps into its native representation. The token→Theme mapping is
## documented in addons/insimul/docs/ui.md; keep the two in lockstep with the JSON.

# ── Colors (hex, matching theme-tokens.json → colors) ────────────────────────
const COLORS := {
	"background": "#12141c",
	"surface": "#1b1e2a",
	"surface_alt": "#242838",
	"overlay": "#0a0b10cc",
	"border": "#333a52",
	"text_primary": "#eef1f8",
	"text_secondary": "#9aa3bd",
	"text_disabled": "#5a6076",
	"accent": "#5b8cff",
	"accent_hover": "#7aa2ff",
	"accent_pressed": "#3f6fe0",
	"success": "#4ecb8d",
	"warning": "#e6b34d",
	"danger": "#e05a6a",
	"quest": "#c9a24b",
}

# ── Spacing (px, matching theme-tokens.json → spacing) ───────────────────────
const SPACING := {"xs": 4, "sm": 8, "md": 12, "lg": 16, "xl": 24}

# ── Corner radii (px) ────────────────────────────────────────────────────────
const RADIUS := {"sm": 4, "md": 8, "lg": 12}

# ── Font sizes (px) ──────────────────────────────────────────────────────────
const FONT_SIZE := {"caption": 12, "body": 16, "title": 22, "display": 32}


static func color(name: String) -> Color:
	return Color(String(COLORS.get(name, "#ffffff")))


## Build a Godot Theme resource from the token set. Wires the semantic tokens into
## the default control theme (font color/size, panel surfaces, button states). The
## mapping is documented in addons/insimul/docs/ui.md.
static func build_theme() -> Theme:
	var theme := Theme.new()

	var text_primary := color("text_primary")
	var text_secondary := color("text_secondary")
	var text_disabled := color("text_disabled")

	# Default label / rich-text foreground + base font size.
	theme.set_color("font_color", "Label", text_primary)
	theme.set_font_size("font_size", "Label", int(FONT_SIZE["body"]))
	theme.set_color("default_color", "RichTextLabel", text_primary)
	theme.set_font_size("normal_font_size", "RichTextLabel", int(FONT_SIZE["body"]))

	# Panel surface.
	var panel_style := _flat(color("surface"), color("border"), int(RADIUS["md"]), int(SPACING["md"]))
	theme.set_stylebox("panel", "PanelContainer", panel_style)
	theme.set_stylebox("panel", "Panel", panel_style)

	# Buttons: accent fill with hover / pressed / disabled states.
	theme.set_stylebox("normal", "Button", _flat(color("accent"), color("border"), int(RADIUS["sm"]), int(SPACING["sm"])))
	theme.set_stylebox("hover", "Button", _flat(color("accent_hover"), color("border"), int(RADIUS["sm"]), int(SPACING["sm"])))
	theme.set_stylebox("pressed", "Button", _flat(color("accent_pressed"), color("border"), int(RADIUS["sm"]), int(SPACING["sm"])))
	theme.set_stylebox("disabled", "Button", _flat(color("surface_alt"), color("border"), int(RADIUS["sm"]), int(SPACING["sm"])))
	theme.set_color("font_color", "Button", text_primary)
	theme.set_color("font_disabled_color", "Button", text_disabled)
	theme.set_font_size("font_size", "Button", int(FONT_SIZE["body"]))

	# Progress bar (loading screen) — accent fill on a recessed surface.
	theme.set_stylebox("background", "ProgressBar", _flat(color("surface_alt"), color("border"), int(RADIUS["sm"]), 0))
	theme.set_stylebox("fill", "ProgressBar", _flat(color("accent"), color("accent"), int(RADIUS["sm"]), 0))
	theme.set_color("font_color", "ProgressBar", text_secondary)

	return theme


## A FlatStyleBox convenience with a border + uniform corner radius + content
## margins (used everywhere the token spacing maps onto a control).
static func _flat(bg: Color, border: Color, radius: int, margin: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	return sb
