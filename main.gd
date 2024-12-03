extends Node

const PlayerScene = preload("res://src/player/player.tscn")

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var player = PlayerScene.instantiate()
	add_child(player)
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
