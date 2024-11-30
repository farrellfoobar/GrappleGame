extends CharacterBody3D


const SPEED = 5.0
const JUMP_VELOCITY = 4.5
const SENSITIVITY = 0.01

var mouse_x = 0
var mouse_last_x

func _physics_process(delta: float) -> void:
	do_look_direction_change()
	do_movment_physics(delta)

	move_and_slide()
	
func do_look_direction_change() -> void:
	if mouse_last_x == null:
		mouse_last_x = get_viewport().get_mouse_position().x
	
	mouse_last_x = mouse_x
	mouse_x = get_viewport().get_mouse_position().x
	var mouse_delta = mouse_last_x - mouse_x
	$Camera3D.rotate(Vector3(0, 1, 0), mouse_delta*SENSITIVITY)

func do_movment_physics(delta: float) -> void:
		# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump.
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var keyboard_input_dir := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	var mouse_input_dir:Vector3 = $Camera3D.project_local_ray_normal(get_viewport().get_mouse_position())
	var mouse_input_dir_normalized:Vector2 = Vector2(mouse_input_dir.x, mouse_input_dir.z)
	var input_dir := keyboard_input_dir * mouse_input_dir_normalized
	var direction := (transform.basis * Vector3(-input_dir.x, 0, input_dir.y)).normalized()
		
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)
