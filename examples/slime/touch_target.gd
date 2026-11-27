extends Area3D
@export_enum("mushroom", "stone", "apple", "crate") var form := "mushroom"
var entry_count := 0

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	if body.has_method("request_form"):
		entry_count += 1
		body.request_form(form)
