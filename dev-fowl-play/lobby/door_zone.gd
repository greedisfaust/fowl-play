class_name DoorZone
extends Area3D

signal countdown_finished             # host only
signal count_changed(seconds: int)    # every machine: >0 counting, 0 go, -1 cancelled

const COUNT_FROM := 5

@onready var door_sign: Screen3D = $Sign

var enabled := true:
	set(v):
		enabled = v
		if enabled:
			_check.call_deferred()

var _inside := {}        # host only: peer id -> true
var _counting := false
var _ticket := 0
var _count := -1
var _inside_n := 0
var _total_n := 1

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	Network.players_changed.connect(_check)
	_refresh()

func _on_body_entered(body: Node3D) -> void:
	if multiplayer.is_server() and body is CharacterBody3D:
		_inside[str(body.name).to_int()] = true
		_check()

func _on_body_exited(body: Node3D) -> void:
	if multiplayer.is_server() and body is CharacterBody3D:
		_inside.erase(str(body.name).to_int())
		_check()

func _check() -> void:
	if not multiplayer.is_server() or not enabled:
		return
	var total := Network.players.size()
	var inside := 0
	for id in _inside:
		if Network.players.has(id):
			inside += 1
	_sync_inside.rpc(inside, total)
	var everyone := total > 0 and inside == total
	if everyone and not _counting:
		_run_countdown()
	elif not everyone and _counting:
		_cancel()

func _run_countdown() -> void:
	_counting = true
	_ticket += 1
	var my_ticket := _ticket
	for s in range(COUNT_FROM, 0, -1):
		_sync_count.rpc(s)
		await get_tree().create_timer(1.0).timeout
		if my_ticket != _ticket:
			return
	_counting = false
	_sync_count.rpc(0)
	countdown_finished.emit()
	await get_tree().create_timer(1.0).timeout
	_reset_sign.rpc()

func _cancel() -> void:
	_counting = false
	_ticket += 1
	_sync_count.rpc(-1)

@rpc("authority", "call_local", "reliable")
func _sync_inside(inside: int, total: int) -> void:
	_inside_n = inside
	_total_n = total
	_refresh()

@rpc("authority", "call_local", "reliable")
func _sync_count(s: int) -> void:
	_count = s
	_refresh()
	count_changed.emit(s)

@rpc("authority", "call_local", "reliable")
func _reset_sign() -> void:
	_count = -1
	_refresh()

func _refresh() -> void:
	if _count > 0:
		door_sign.set_text(str(_count), "HEADING OUT...")
		door_sign.set_color(Color(0.3, 1.0, 0.45))
	elif _count == 0:
		door_sign.set_text("GO!", "")
		door_sign.set_color(Color(0.3, 1.0, 0.45))
	else:
		door_sign.set_text("DOOR", "EVERYONE MUST STAND ON THE PAD\n(%d/%d INSIDE)" % [_inside_n, _total_n])
		door_sign.set_color(Color(1.0, 0.85, 0.3))
