extends TableBase

const LANES := 12
const START_X := -1.38
const TILE_SPACING := 0.23
const HOP_TIME := 0.35
const CHICKEN_REST := Vector3(0, 0.17, 0)

const BUST_CHANCE := [0.07, 0.09, 0.11, 0.14, 0.17, 0.20, 0.24, 0.28, 0.32, 0.37, 0.42, 0.48]
# TEMP: the GDD only gives the ends (1.3x and 15x). Paste your economy-sheet numbers here.
const MULTIPLIER := [1.3, 1.6, 2.0, 2.5, 3.2, 4.0, 5.0, 6.2, 7.7, 9.6, 12.0, 15.0]

var lane := 0          # host only: current lane (0 = the curb)
var _busy := false     # host only: true while a hop or payout is playing

@onready var chicken: Node3D = $Road/Chicken
@onready var status: Screen3D = $StatusScreen

func _on_table_ready() -> void:
	for i in range(1, LANES + 1):
		var tile := MeshInstance3D.new()
		var tile_mesh := BoxMesh.new()
		tile_mesh.size = Vector3(0.2, 0.02, 0.4)
		tile.mesh = tile_mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.25, 0.25, 0.3) if i % 2 == 0 else Color(0.4, 0.4, 0.45)
		tile.material_override = mat
		tile.position = slot_position(i) + Vector3(0, 0.04, 0)
		$Road.add_child(tile)
	chicken.position = slot_position(0) + CHICKEN_REST
	$Buttons/ProceedButton.pressed.connect(_on_proceed_pressed)
	$Buttons/CashOutButton.pressed.connect(_on_cash_out_pressed)
	status.set_text("PLACE YOUR BET", display_name)

func slot_position(i: int) -> Vector3:
	return Vector3(START_X + i * TILE_SPACING, 0.0, 0.0)

# ---------- input (runs on the player who pressed) ----------
func _on_proceed_pressed(_v: int) -> void:
	send_action("proceed", {"seen_bet": get_total_bet()})

func _on_cash_out_pressed(_v: int) -> void:
	send_action("cash_out")

# ---------- rules (host only) ----------
func _on_round_start(_who: int, _total: int) -> void:
	lane = 0
	_busy = false
	emit_event("round_started")

func _on_player_action(who: int, action: String, data: Dictionary) -> void:
	if not running:
		if action == "proceed" and start_round(who, data.get("seen_bet", -1)):
			_proceed()
		return
	if _busy:
		return
	if action == "proceed":
		_proceed()
	elif action == "cash_out" and lane > 0:
		_end_round(_payout_for(lane))

func _proceed() -> void:
	_busy = true
	lane += 1
	var chance: float = BUST_CHANCE[lane - 1]
	var busted: bool = randf() < chance
	emit_event("hop", {"lane": lane, "bust": busted})
	await get_tree().create_timer(HOP_TIME + 0.5).timeout
	if busted:
		await _end_round(0)
	elif lane == LANES:
		await _end_round(_payout_for(lane))
	else:
		_busy = false

func _end_round(payout: int) -> void:
	_busy = true
	emit_event("round_over", {"payout": payout})
	await get_tree().create_timer(1.0).timeout
	finish_round(payout)
	_busy = false

func _payout_for(l: int) -> int:
	var mult: float = MULTIPLIER[l - 1]
	return roundi(locked_bet * mult)

# ---------- visuals (runs on every machine) ----------
func _on_event(event: String, data: Dictionary) -> void:
	match event:
		"round_started":
			chicken.visible = true
			chicken.position = slot_position(0) + CHICKEN_REST
			status.set_text("HOP OR CASH OUT", display_name)
		"hop":
			_hop_to(data.lane)
			await get_tree().create_timer(HOP_TIME).timeout
			if data.bust:
				await _crash_car(data.lane)
				status.set_text("SPLAT!", display_name)
			else:
				status.set_text("LANE %d   x%.1f" % [data.lane, MULTIPLIER[data.lane - 1]], display_name)
		"round_over":
			if data.payout > 0:
				status.set_text("CASHED OUT $%d" % data.payout, display_name)

func _hop_to(target_lane: int) -> void:
	var end_x := slot_position(target_lane).x
	var tx := create_tween()
	tx.tween_property(chicken, "position:x", end_x, HOP_TIME)
	var ty := create_tween()
	ty.tween_property(chicken, "position:y", CHICKEN_REST.y + 0.12, HOP_TIME * 0.5).set_ease(Tween.EASE_OUT)
	ty.tween_property(chicken, "position:y", CHICKEN_REST.y, HOP_TIME * 0.5).set_ease(Tween.EASE_IN)

func _crash_car(target_lane: int) -> void:
	var car := MeshInstance3D.new()
	var body := BoxMesh.new()
	body.size = Vector3(0.16, 0.08, 0.26)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.1, 0.1)
	body.material = mat
	car.mesh = body
	car.position = Vector3(slot_position(target_lane).x, 0.07, -0.3)
	$Road.add_child(car)
	var drive := create_tween()
	drive.tween_property(car, "position:z", 0.0, 0.25).set_ease(Tween.EASE_IN)
	await drive.finished
	chicken.visible = false
	_explode_at(chicken.position)
	var leave := create_tween()
	leave.tween_property(car, "position:z", 0.45, 0.2)
	await leave.finished
	car.queue_free()

func _explode_at(pos: Vector3) -> void:
	var p := CPUParticles3D.new()
	var piece := BoxMesh.new()
	piece.size = Vector3(0.03, 0.03, 0.03)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.1)
	piece.material = mat
	p.mesh = piece
	p.amount = 40
	p.lifetime = 0.9
	p.one_shot = true
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.5
	p.gravity = Vector3(0, -6, 0)
	p.position = pos
	$Road.add_child(p)
	p.emitting = true
	await get_tree().create_timer(1.5).timeout
	p.queue_free()
