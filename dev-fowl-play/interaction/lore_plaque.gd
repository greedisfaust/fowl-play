class_name LorePlaque
extends StaticBody3D

@export var title := "HOUSE NOTICE"
@export_multiline var body := ""

func _ready() -> void:
	add_to_group("lore_guides")

func interact(player: Node) -> void:
	player.read_lore(title, body)

func get_interaction_prompt(_player: Node) -> String:
	return "Read " + title
