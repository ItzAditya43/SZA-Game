extends Control
## A small line chart over days: one series, axes labelled with the first and
## last day and the min/max value. Drawn directly; no plugins.

const Tokens := preload("res://ui/theme/tokens.gd")

var title: String = ""
var unit: String = ""
var points: Array = []  # [[day: float, value: float], ...]
var color: Color = Tokens.INFO


func _ready() -> void:
	custom_minimum_size = Vector2(200, 110)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func set_series(new_points: Array) -> void:
	points = new_points
	queue_redraw()


func _draw() -> void:
	var font: Font = get_theme_default_font()
	var small: int = Tokens.FONT_SMALL
	draw_string(font, Vector2(0, small), title, HORIZONTAL_ALIGNMENT_LEFT, -1, small, Tokens.TEXT)
	var area: Rect2 = Rect2(36, small + 6, size.x - 40, size.y - small - 22)
	draw_rect(area, Tokens.BG_APP)
	if points.size() < 2:
		draw_string(font, area.position + Vector2(6, area.size.y / 2), "Not enough days yet", HORIZONTAL_ALIGNMENT_LEFT, -1, small, Tokens.TEXT_FAINT)
		return
	var lo: float = INF
	var hi: float = -INF
	for p: Array in points:
		lo = minf(lo, float(p[1]))
		hi = maxf(hi, float(p[1]))
	lo = minf(lo, 0.0)
	if is_equal_approx(hi, lo):
		hi = lo + 1.0
	var d0: float = float(points[0][0])
	var d1: float = maxf(float(points[-1][0]), d0 + 1.0)
	var line: PackedVector2Array = []
	for p: Array in points:
		var x: float = area.position.x + (float(p[0]) - d0) / (d1 - d0) * area.size.x
		var y: float = area.end.y - (float(p[1]) - lo) / (hi - lo) * area.size.y
		line.append(Vector2(x, y))
	draw_polyline(line, color, 2.0, true)
	draw_circle(line[-1], 3.0, color)
	draw_string(font, Vector2(0, area.position.y + small), _short(hi), HORIZONTAL_ALIGNMENT_LEFT, 34, small, Tokens.TEXT_MUTED)
	draw_string(font, Vector2(0, area.end.y), _short(lo), HORIZONTAL_ALIGNMENT_LEFT, 34, small, Tokens.TEXT_MUTED)
	draw_string(font, Vector2(area.position.x, size.y - 2), "Day %d" % roundi(d0), HORIZONTAL_ALIGNMENT_LEFT, -1, small, Tokens.TEXT_MUTED)
	draw_string(font, Vector2(area.position.x, size.y - 2), "Day %d: %s %s" % [roundi(float(points[-1][0])), _short(float(points[-1][1])), unit],
		HORIZONTAL_ALIGNMENT_RIGHT, area.size.x, small, Tokens.TEXT)


static func _short(value: float) -> String:
	if absf(value) >= 10000.0:
		return "%dk" % roundi(value / 1000.0)
	if absf(value) >= 100.0:
		return str(roundi(value))
	return str(snappedf(value, 0.1))
