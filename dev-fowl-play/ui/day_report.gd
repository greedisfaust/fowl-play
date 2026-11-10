class_name DayReport
extends CanvasLayer

const AWARD_W := 640.0
const QUIPS_PASS := ["THE HOUSE IS... DISPLEASED.", "THE HOUSE WILL REMEMBER THIS.", "ENJOY IT WHILE IT LASTS."]
const QUIPS_FAIL := ["THE HOUSE THANKS YOU FOR YOUR CONTRIBUTION.", "THE HOUSE NEVER LOSES.", "BETTER LUCK TOMORROW. OR NOT."]

var _skipped := false
var _root: Control
var _title: Label
var _awards: VBoxContainer
var _award_nodes: Array[RichTextLabel] = []
var _chart: ReportChart
var _verdict: RichTextLabel
var _final_pos := Vector2.ZERO
var _final_scale := 1.0
var _start_scale := 1.0

func play(s: Dictionary) -> void:
	layer = 11   # above the HUD fade layer
	_build(s)
	await get_tree().process_frame
	await get_tree().process_frame   # let the root settle to full-screen size
	_layout()
	await _sequence(s)

func skip() -> void:
	_skipped = true

# ---------- building ----------
func _build(s: Dictionary) -> void:
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_title = Label.new()
	_title.text = "DAY %d REPORT" % s.day
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 44)
	if Style.font:
		_title.add_theme_font_override("font", Style.font)
	_title.modulate.a = 0.0
	_root.add_child(_title)

	_awards = VBoxContainer.new()
	_awards.add_theme_constant_override("separation", 14)
	_awards.custom_minimum_size.x = AWARD_W
	_root.add_child(_awards)
	for line in _award_lines(s):
		var r := _rich(26)
		r.fit_content = true
		r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		r.custom_minimum_size.x = AWARD_W
		r.text = line
		r.modulate.a = 0.0
		_awards.add_child(r)
		_award_nodes.append(r)

	if s.rounds > 0:
		_chart = ReportChart.new()
		_chart.modulate.a = 0.0
		_root.add_child(_chart)
		_chart.setup(s)

	_verdict = _rich(30)
	_verdict.text = _verdict_text(s)
	_verdict.modulate.a = 0.0
	_root.add_child(_verdict)

func _rich(font_size: int) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.scroll_active = false
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_theme_font_size_override("normal_font_size", font_size)
	r.add_theme_color_override("default_color", Color.WHITE)
	if Style.font:
		r.add_theme_font_override("normal_font", Style.font)
	return r

func _layout() -> void:
	var vw := _root.size.x
	var vh := _root.size.y
	var top := 110.0
	var area_h := vh - 190.0 - top
	var mx := vw * 0.05
	var gap := vw * 0.04
	_title.position = Vector2(0, 30)
	_title.size = Vector2(vw, 60)

	var aw_h := _awards.get_combined_minimum_size().y
	_awards.size = Vector2(AWARD_W, aw_h)
	_start_scale = minf(1.0, area_h / maxf(aw_h, 1.0))   # shrink if the column is too tall
	_awards.scale = Vector2(_start_scale, _start_scale)
	_awards.position = Vector2((vw - AWARD_W * _start_scale) / 2.0, top + (area_h - aw_h * _start_scale) / 2.0)

	_final_scale = minf(clampf(vw * 0.32 / AWARD_W, 0.4, 1.0), _start_scale)
	_final_pos = Vector2(mx, top + (area_h - aw_h * _final_scale) / 2.0)
	var left_w := AWARD_W * _final_scale

	_verdict.position = Vector2(0, vh - 170)
	_verdict.size = Vector2(vw, 150)
	if _chart:
		var cx := mx + left_w + gap
		_chart.position = Vector2(cx, top)
		_chart.size = Vector2(vw - mx - cx, area_h)

# ---------- text ----------
func _nm(d: Dictionary) -> String:
	var c: Color = d.color
	return "[color=#%s]%s[/color]" % [c.to_html(false), String(d.name).replace("[", "[lb]")]

func _award(head: String, body: String) -> String:
	return "[color=#8a8a8a][font_size=18]%s[/font_size][/color]\n%s" % [head, body]

func _award_lines(s: Dictionary) -> Array:
	if s.rounds == 0:
		return [_award("NO ROUNDS", "NOBODY PLAYED A SINGLE ROUND")]
	var fixed: Array = []
	var extra: Array = []
	if not s.best.is_empty():
		fixed.append(_award("BEST WIN", "%s won $%d at %s" % [_nm(s.best), s.best.gain, s.best.table]))
	if not s.worst.is_empty():
		fixed.append(_award("BIGGEST LOSS", "%s lost $%d at %s" % [_nm(s.worst), -s.worst.gain, s.worst.table]))
	if not s.greedy.is_empty():
		var ending := "and went SPLAT" if s.greedy.bust else "and cashed out"
		extra.append(_award("GREEDIEST", "%s pushed %d deep at %s %s" % [_nm(s.greedy), s.greedy.depth, s.greedy.table, ending]))
	if not s.unlucky.is_empty():
		extra.append(_award("UNLUCKIEST BUST", "%s busted at depth %d (only a %d%% chance)" % [_nm(s.unlucky), s.unlucky.depth, roundi(s.unlucky.chance * 100.0)]))
	if not s.liability.is_empty():
		extra.append(_award("BIGGEST LIABILITY", "%s lost $%d overall" % [_nm(s.liability), -s.liability.gain]))
	if not s.lucky.is_empty():
		extra.append(_award("LUCKY DUCK", "%s is up $%d overall" % [_nm(s.lucky), s.lucky.gain]))
	for n in s.notes:
		extra.append(_award(String(n.table).to_upper(), "%s %s" % [_nm(n), n.note]))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(s.day) * 7919 + int(s.rounds)
	for i in range(extra.size() - 1, 0, -1):   # seeded shuffle, same result on every machine
		var j := rng.randi_range(0, i)
		var tmp = extra[i]
		extra[i] = extra[j]
		extra[j] = tmp
	return (fixed + extra).slice(0, 4)

func _verdict_text(s: Dictionary) -> String:
	var diff: int = s.wallet - s.quota
	var head := "QUOTA $%d   FINAL $%d" % [s.quota, s.wallet]
	if diff >= 0:
		return "[center]%s\nPASSED WITH $%d SPARE\n[color=#8a8a8a]%s[/color][/center]" % [head, diff, QUIPS_PASS[s.day % QUIPS_PASS.size()]]
	return "[center]%s\nMISSED BY $%d\n[color=#8a8a8a]%s[/color][/center]" % [head, -diff, QUIPS_FAIL[s.day % QUIPS_FAIL.size()]]

# ---------- the show ----------
func _wait(secs: float) -> void:
	var left := secs
	while left > 0.0 and not _skipped:
		await get_tree().create_timer(0.1).timeout
		left -= 0.1

func _fade(n: CanvasItem, secs: float) -> void:
	create_tween().tween_property(n, "modulate:a", 1.0, secs)

func _sequence(s: Dictionary) -> void:
	_fade(_title, 0.6)
	await _wait(1.4)
	for r in _award_nodes:
		_fade(r, 0.4)
		await _wait(1.3)
	await _wait(0.7)
	if _chart:
		var t := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		t.tween_property(_awards, "position", _final_pos, 1.0)
		t.tween_property(_awards, "scale", Vector2(_final_scale, _final_scale), 1.0)
		await _wait(1.2)
		_fade(_chart, 0.6)
		await _wait(0.7)
		var dur := clampf(1.5 + s.rounds * 0.8, 3.0, 8.0)
		create_tween().tween_property(_chart, "progress", 1.0, dur)
		await _wait(dur + 0.8)
	_fade(_verdict, 0.6)
	await _wait(4.5)
	var out := create_tween()
	out.tween_property(_root, "modulate:a", 0.0, 0.3 if _skipped else 1.0)
	await out.finished
	await get_tree().create_timer(0.3).timeout
