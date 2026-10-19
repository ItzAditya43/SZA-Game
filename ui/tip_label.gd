extends Label
## A label whose hover tooltip explains the number it shows: the breakdown's
## contributions, the total and any forecast (see core/insight.gd).

const TipPanel := preload("res://ui/tip_panel.gd")

var breakdown: Dictionary = {}:
	set(value):
		breakdown = value
		tooltip_text = " " if not value.is_empty() else ""
		mouse_filter = Control.MOUSE_FILTER_PASS if not value.is_empty() else Control.MOUSE_FILTER_IGNORE


func _make_custom_tooltip(_for_text: String) -> Object:
	return TipPanel.build(breakdown)
