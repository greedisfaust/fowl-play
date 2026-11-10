class_name Crosshair
extends Control
## White translucent ring at rest. Eases larger, glows and takes the player's color on hover.

var _hover := 0.0
var _target := 0.0

func set_hover(v: bool) -> void:
	_target = 1.0 if v else 0.0

func _process(delta: float) -> void:
	if not visible:
		return
	_hover = move_toward(_hover, _target, delta * 9.0)
	queue_redraw()

func _draw() -> void:
	var mine := Network.player_color(multiplayer.get_unique_id())
	var col := Color.WHITE.lerp(mine, _hover)
	var r := lerpf(5.0, 9.0, _hover)
	if _hover > 0.01:   # soft glow rings
		for k in 3:
			draw_circle(Vector2.ZERO, r + 3.0 + k * 3.0, Color(col, 0.10 * _hover))
	draw_circle(Vector2.ZERO, r, Color(col, 0.22))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, col, 1.8, true)
