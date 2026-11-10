class_name ReportChart
extends Control

const ML := 16.0
const MT := 56.0
const MR := 16.0
const MB := 50.0

var progress := 0.0:
	set(v):
		progress = v
		queue_redraw()

var _series := {}       # name -> {"color": Color, "pts": Array of Vector2(t, running net), "sum": float}
var _team: Array = []
var _quota_gain := 0.0
var _t_end := 1.0
var _y_min := 0.0
var _y_max := 1.0

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func setup(s: Dictionary) -> void:
	_series.clear()
	_team = [Vector2(0, 0)]
	var team_sum := 0.0
	_t_end = 1.0
	for e in s.events:
		var n: String = e.name
		if not _series.has(n):
			_series[n] = {"color": e.color, "pts": [Vector2(0, 0)], "sum": 0.0}
		var sr: Dictionary = _series[n]
		sr.sum += e.gain
		sr.pts.append(Vector2(e.t, sr.sum))
		team_sum += e.gain
		_team.append(Vector2(e.t, team_sum))
		_t_end = maxf(_t_end, e.t)
	_t_end *= 1.06   # the chart ends at the last action, not the full day length
	_quota_gain = float(s.quota - s.start_wallet)
	_y_min = 0.0
	_y_max = maxf(_quota_gain, 1.0)
	var all: Array = _team.duplicate()
	for n in _series:
		all.append_array(_series[n].pts)
	for p in all:
		_y_min = minf(_y_min, p.y)
		_y_max = maxf(_y_max, p.y)
	var pad := maxf(_y_max - _y_min, 100.0) * 0.12
	_y_max += pad
	if _y_min < 0.0:
		_y_min -= pad
	queue_redraw()

func _plot() -> Rect2:
	return Rect2(ML, MT, size.x - ML - MR, size.y - MT - MB)

func _px(t: float, v: float) -> Vector2:
	var r := _plot()
	return Vector2(
		r.position.x + r.size.x * t / _t_end,
		r.end.y - r.size.y * (v - _y_min) / (_y_max - _y_min))

func _visible_points(pts: Array, t_now: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in pts.size():
		var p: Vector2 = pts[i]
		if p.x <= t_now:
			out.append(_px(p.x, p.y))
		else:
			if i > 0:
				var a: Vector2 = pts[i - 1]
				var f := (t_now - a.x) / maxf(p.x - a.x, 0.0001)
				out.append(_px(t_now, lerpf(a.y, p.y, f)))
			break
	return out

func _draw() -> void:
	var font: Font = Style.font if Style.font else ThemeDB.fallback_font
	var r := _plot()
	draw_rect(r, Color(1, 1, 1, 0.04))
	draw_rect(r, Color(1, 1, 1, 0.25), false, 1.0)
	var zero_y := _px(0, 0).y
	draw_line(Vector2(r.position.x, zero_y), Vector2(r.end.x, zero_y), Color(1, 1, 1, 0.5), 1.5)
	draw_string(font, Vector2(r.position.x + 8, zero_y - 6), "$0", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.7))
	var qy := _px(0, _quota_gain).y
	draw_dashed_line(Vector2(r.position.x, qy), Vector2(r.end.x, qy), Color(1, 1, 1, 0.6), 2.0, 10.0)
	draw_string(font, Vector2(r.end.x - 206, qy - 6), "QUOTA +$%d" % int(_quota_gain), HORIZONTAL_ALIGNMENT_RIGHT, 198, 14, Color(1, 1, 1, 0.7))
	var t_label := "%d:%02d" % [floori(_t_end / 60.0), int(_t_end) % 60]
	draw_string(font, Vector2(r.position.x, r.end.y + 26), "0:00", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.6))
	draw_string(font, Vector2(r.end.x - 100, r.end.y + 26), t_label, HORIZONTAL_ALIGNMENT_RIGHT, 100, 16, Color(1, 1, 1, 0.6))

	var t_now := _t_end * progress
	var team_pts := _visible_points(_team, t_now)   # the faint team line (delete these 3 lines to remove it)
	if team_pts.size() >= 2:
		draw_polyline(team_pts, Color(1, 1, 1, 0.28), 2.0, true)

	var lx := r.position.x + 12.0
	for n in _series:
		var col: Color = _series[n].color
		var pts: Array = _series[n].pts
		var vis := _visible_points(pts, t_now)
		if vis.size() >= 2:
			draw_polyline(vis, col, 3.0, true)
		for i in range(1, pts.size()):
			var p: Vector2 = pts[i]
			if p.x > t_now:
				break
			var prev: Vector2 = pts[i - 1]
			var gain := p.y - prev.y
			var pos := _px(p.x, p.y)
			draw_circle(pos, 4.0, col)
			var txt := "%s$%d" % ["+" if gain >= 0.0 else "-", absi(int(gain))]
			draw_string(font, pos + Vector2(-20, -10 if gain >= 0.0 else 22), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, col)
		draw_rect(Rect2(lx, r.position.y - 36, 14, 14), col)
		draw_string(font, Vector2(lx + 20, r.position.y - 23), n, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
		lx += 20.0 + font.get_string_size(n, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 24.0
	draw_line(Vector2(lx, r.position.y - 29), Vector2(lx + 14, r.position.y - 29), Color(1, 1, 1, 0.28), 2.0)
	draw_string(font, Vector2(lx + 20, r.position.y - 23), "TEAM", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.5))
