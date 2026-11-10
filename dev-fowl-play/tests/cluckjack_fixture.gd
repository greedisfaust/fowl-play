extends "res://tables/cluckjack/cluckjack.gd"
## Deterministic host fixture; never used by production scenes.
var next_deck: Array[int] = [9, 22, 6, 18, 35]

func _on_round_start(_who: int, _total: int) -> void:
	hand.begin(next_deck)
	_publish_or_finish()
