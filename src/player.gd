extends CharacterBody3D


const SPEED = 5.0
const JUMP_VELOCITY = 4.5
const SENSITIVITY = 0.01

var player: Node3D

var mouse_x = 0
var mouse_last_x = 0

func _enter_tree() -> void:
	player = get_node(".")

func _physics_process(delta: float) -> void:
	impart_gravity(delta)
	do_look_direction_change()
	impart_velocity_from_inputs()
	move_and_slide() # tell godot to handle the physics
	
func do_look_direction_change() -> void:
	mouse_last_x = mouse_x
	mouse_x = get_viewport().get_mouse_position().x
	var mouse_delta = mouse_last_x - mouse_x
	player.rotate(Vector3(0, 1, 0), mouse_delta*SENSITIVITY)

func impart_velocity_from_inputs() -> void:
	impart_jump()
	impart_cardinal_movement()
	
func impart_gravity(delta: float):
	if not is_on_floor():
		velocity += get_gravity() * delta
		
func impart_jump():
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY
		
func impart_cardinal_movement():
	var input_dir := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	var direction := (player.transform.basis * Vector3(-input_dir.x, 0, input_dir.y)).normalized()

	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)