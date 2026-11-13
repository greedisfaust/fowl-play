class_name LorePlaque
extends StaticBody3D

@export var title := "HOUSE NOTICE"
@export_multiline var body := ""

func _ready() -> void:
	collision_layer = 2   # DEVICES layer so the focus ray can hit plaques
	add_to_group("lore_guides")
	# Expose the single Interactable contract (R1).
	var interactable := Interactable.new()
	interactable.kind = Interactable.Kind.USE
	add_child(interactable)

func interact(player: Node) -> void:
	player.read_lore(title, body)

func get_interaction_prompt(_player: Node) -> String:
	return "Read " + title
