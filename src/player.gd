extends CharacterBody3D


const SPEED = 5.0
const JUMP_VELOCITY = 40
const SENSITIVITY = 0.01

var player: Node3D


func _enter_tree() -> void:
	player = get_node(".")

func _physics_process(delta: float) -> void:
	impart_gravity(delta)
	do_look_direction_change()
	impart_velocity_from_inputs()
	impart_velocity_from_grapple(delta)
	move_and_slide() # tell godot to handle the physics

var mouse_x: int      = 0
var mouse_last_x: int = 0
var mouse_y: int      = 0
var mouse_last_y: int = 0
func do_look_direction_change() -> void:
	mouse_last_x = mouse_x
	mouse_last_y = mouse_y
	mouse_x = get_viewport().get_mouse_position().x
	mouse_y = get_viewport().get_mouse_position().y
	var mouse_x_delta: int = mouse_last_x - mouse_x
	var mouse_y_delta: int = mouse_last_y - mouse_y
	player.rotate(Vector3(0, 1, 0), mouse_x_delta*SENSITIVITY)
	player.rotate_object_local(Vector3(1, 0, 0), mouse_y_delta*SENSITIVITY)

func impart_velocity_from_inputs() -> void:
	impart_jump()
	impart_cardinal_movement()

var is_grappled: bool          = false
var grapple_rest_length: float = 0
var grapple_extension: float   = 0
var pull_vector: Vector3
var tension_force: Vector3
var mesh: ImmediateMesh = ImmediateMesh.new()
func impart_velocity_from_grapple(delta: float) -> void:
	if(is_grappled):
		pull_vector = get_grapple_path().normalized()
		grapple_extension = get_grapple_path().length() - grapple_rest_length
		if(grapple_extension > 0):
			tension_force = get_grapple_path() * (get_gravity().length()/get_grapple_path().length())
			tension_force = tension_force * (1 + sin(pull_vector.angle_to(get_gravity())))
			#print("t, e: ", tension_force.y, ", ", grapple_extension, ", ", grapple_rest_length)
			velocity += tension_force * delta * grapple_extension
			
	if Input.is_action_just_pressed("grapple"):
		line(player.global_position, get_node("grapple_target").global_position)
		grapple_rest_length = get_grapple_path().length()
		is_grappled = true
		
	if Input.is_action_just_released("grapple"):
		is_grappled = false
	

func get_grapple_path() -> Vector3:
	var grapple_target: Vector3 = get_node("grapple_target").global_position;
	return grapple_target - player.global_position
		
func impart_gravity(delta: float):
	if not is_on_floor():
		velocity += get_gravity() * delta
		
func impart_jump():
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y += JUMP_VELOCITY
		
func impart_cardinal_movement():
	var input_dir := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	var direction := (player.transform.basis * Vector3(-input_dir.x, 0, input_dir.y)).normalized()

	if direction and is_on_floor:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	elif(!is_grappled && is_on_floor()):
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

func line(pos1: Vector3, pos2: Vector3, color = Color.RED, persist_ms = 0):
	var mesh_instance := MeshInstance3D.new()
	var immediate_mesh := ImmediateMesh.new()
	var material := ORMMaterial3D.new()

	mesh_instance.mesh = immediate_mesh
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	immediate_mesh.surface_add_vertex(pos1)
	immediate_mesh.surface_add_vertex(pos2)
	immediate_mesh.surface_end()

	get_tree().get_root().add_child(mesh_instance)

	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
