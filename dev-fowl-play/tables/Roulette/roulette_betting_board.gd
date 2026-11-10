class_name RouletteBettingBoard
extends Node3D

signal bet_selected(bet_type: String, numbers: Array, payout: int)

const KEY_SCENE := preload("res://tables/press_button.tscn")

# Layout
const TILE_WIDTH := 0.32
const TILE_DEPTH := 0.24
const TILE_HEIGHT := 0.06
const GAP := 0.025

const GREEN := Color(0.12, 0.65, 0.2)
const RED := Color(0.85, 0.12, 0.16)
const BLACK := Color(0.09, 0.09, 0.11)
const GOLD := Color(0.8, 0.65, 0.2)

# European roulette colors
const RED_NUMBERS: Array[int] = [
	1, 3, 5, 7, 9, 12, 14, 16, 18,
	19, 21, 23, 25, 27, 30, 32, 34, 36
]

func _ready() -> void:
	_build_board()

func _build_board() -> void:
	_build_felt()
	_build_zero()
	_build_numbers()
	_build_outside_bets()
	_build_dozens()
	_build_columns()

func _build_felt() -> void:
	var felt := MeshInstance3D.new()
	var mesh := BoxMesh.new()

	mesh.size = Vector3(4.25, 0.08, 1.65)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.025, 0.3, 0.12)
	mesh.material = mat

	felt.mesh = mesh
	felt.position.y = -0.06
	add_child(felt)

func _build_zero() -> void:
	_make_tile(
		"0",
		"straight",
		[0],
		35,
		GREEN,
		Vector3(-1.91, 0.02, 0),
		Vector3(0.32, 0.06, 0.77)
	)

func _build_numbers() -> void:
	# 12 columns, 3 rows
	# Layout: 1,2,3 | 4,5,6 | ... | 34,35,36

	for column in range(12):
		for row in range(3):
			var number := column * 3 + row + 1

			var color := RED if number in RED_NUMBERS else BLACK

			var pos := Vector3(
				-1.55 + column * (TILE_WIDTH + GAP),
				0.02,
				-0.52 + row * (TILE_DEPTH + GAP)
			)

			_make_tile(
				str(number),
				"straight",
				[number],
				35,
				color,
				pos,
				Vector3(TILE_WIDTH, TILE_HEIGHT, TILE_DEPTH)
			)

func _build_outside_bets() -> void:
	var z := 0.43
	var depth := 0.25

	var bets := [
		["1-18", "low", _range(1, 18), 1],
		["EVEN", "even", _even_numbers(), 1],
		["RED", "red", RED_NUMBERS, 1],
		["BLACK", "black", _black_numbers(), 1],
		["ODD", "odd", _odd_numbers(), 1],
		["19-36", "high", _range(19, 36), 1]
	]

	for i in range(bets.size()):
		var x := -1.55 + i * 0.65

		_make_tile(
			bets[i][0],
			bets[i][1],
			bets[i][2],
			bets[i][3],
			GOLD if i == 0 or i == 5 else RED if i == 2 else BLACK,
			Vector3(x, 0.02, z),
			Vector3(0.60, TILE_HEIGHT, depth)
		)

func _build_dozens() -> void:
	var bets := [
		["1ST 12", "dozen", _range(1, 12), 2],
		["2ND 12", "dozen", _range(13, 24), 2],
		["3RD 12", "dozen", _range(25, 36), 2]
	]

	for i in range(3):
		_make_tile(
			bets[i][0],
			bets[i][1],
			bets[i][2],
			bets[i][3],
			GOLD,
			Vector3(-1.55 + i * 1.30, 0.02, 0.78),
			Vector3(1.25, TILE_HEIGHT, 0.22)
		)

func _build_columns() -> void:
	for column in range(3):
		var numbers: Array[int] = []

		for row in range(12):
			numbers.append(row * 3 + column + 1)

		_make_tile(
			"2:1",
			"column",
			numbers,
			2,
			GOLD,
			Vector3(1.85, 0.02, -0.52 + column * 0.28),
			Vector3(0.30, TILE_HEIGHT, 0.24)
		)

func _make_tile(
	label: String,
	bet_type: String,
	numbers: Array,
	payout: int,
	color: Color,
	pos: Vector3,
	tile_size: Vector3
) -> void:
	var tile := KEY_SCENE.instantiate() as PressButton

	tile.label_text = label
	tile.button_color = color
	tile.size = tile_size
	tile.position = pos
	tile.label_font_size = 22

	tile.pressed.connect(
		_on_tile_pressed.bind(bet_type, numbers, payout)
	)

	add_child(tile)

func _on_tile_pressed(
	_value: int,
	bet_type: String,
	numbers: Array,
	payout: int
) -> void:
	bet_selected.emit(bet_type, numbers, payout)

func _range(first: int, last: int) -> Array[int]:
	var result: Array[int] = []

	for n in range(first, last + 1):
		result.append(n)

	return result

func _even_numbers() -> Array[int]:
	var result: Array[int] = []

	for n in range(2, 37, 2):
		result.append(n)

	return result

func _odd_numbers() -> Array[int]:
	var result: Array[int] = []

	for n in range(1, 37, 2):
		result.append(n)

	return result

func _black_numbers() -> Array[int]:
	var result: Array[int] = []

	for n in range(1, 37):
		if n not in RED_NUMBERS:
			result.append(n)

	return result
