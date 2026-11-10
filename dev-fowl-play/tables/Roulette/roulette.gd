extends Node3D

func _ready() -> void:
	$BettingBoard.bet_selected.connect(_on_bet_selected)

func _on_bet_selected(
	bet_type: String,
	numbers: Array,
	payout: int
) -> void:
	print("Bet type: ", bet_type)
	print("Numbers: ", numbers)
	print("Payout: ", payout)
