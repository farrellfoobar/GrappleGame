class_name Player
extends CharacterBody3D

enum ANIMATIONS {JUMP_UP, JUMP_DOWN, STRAFE, WALK}

const DIRECTION_INTERPOLATE_SPEED = 1
const MOTION_INTERPOLATE_SPEED = 10
const ROTATION_INTERPOLATE_SPEED = 10

const MIN_AIRBORNE_TIME = 0.1
const MIN_AIR_TIME_FOR_LANDING_ANIMATION = 0.5
const JUMP_SPEED = 16


@onready var initial_position = transform.origin
@onready var gravity = ProjectSettings.get_setting("physics/3d/default_gravity") * ProjectSettings.get_setting("physics/3d/default_gravity_vector")

@onready var player_input = $InputSynchronizer
@onready var animation_tree = $AnimationTree
@onready var player_model = $PlayerModel
@onready var shoot_from = player_model.get_node("Robot_Skeleton/Skeleton3D/GunBone/ShootFrom")
@onready var crosshair = $Crosshair
@onready var fire_cooldown = $FireCooldown

@onready var sound_effects = $SoundEffects
@onready var sound_effect_jump = sound_effects.get_node("Jump")
@onready var sound_effect_land = sound_effects.get_node("Land")
@onready var sound_effect_shoot = sound_effects.get_node("Shoot")

@export var player_id := 1 :
	set(value):
		player_id = value
		$InputSynchronizer.set_multiplayer_authority(value)

@export var current_animation := ANIMATIONS.WALK

# This script is a very refactored version of https://github.com/godotengine/tps-demo/blob/master/player/player.gd
# Other than the ability to jump while walking it should be 1:1 with that player, the only known issue being that while
# in the air and not aiming, you can still change your direction for some reason. Doesnt work while aming tho idk

func _ready():
	orientation = player_model.global_transform
	orientation.origin = Vector3()


func _physics_process(delta: float):
	# If we're below -40, respawn (teleport to the initial position).
	if transform.origin.y < -40:
		transform.origin = initial_position
		
	apply_input(delta)

func apply_input(delta: float):
	rotate_player_from_input(delta)
	do_jump_logic(delta)
	handle_sprint()
	apply_input_to_character(delta)
	#print("v1: ", velocity)
	animate_player()
	handle_shoot()
	impart_velocity_from_grapple(delta)
	#print("v2: ", velocity)
	move_and_slide()


func rotate_player_from_input(delta: float):
	if player_input.aiming:
		rotate_character_with_locked_camera(delta)
	else:
		rotate_character_with_independent_camera(delta)


var airborne_time: float     = 100
func do_jump_logic(delta: float):
	if is_on_floor():
		if is_landing():
			player_input.jumping = false
		elif player_input.jumping:
			velocity.y = JUMP_SPEED
		airborne_time = 0
	elif is_grappled and Input.is_action_just_pressed("jump"):
		is_grappled = false
		velocity.y += JUMP_SPEED
		root_motion = Transform3D(animation_tree.get_root_motion_rotation(), animation_tree.get_root_motion_position())
		orientation *= root_motion
		var horizontal_velocity: Vector3 = orientation.origin / delta
		velocity.x += horizontal_velocity.x * 10
		velocity.z += horizontal_velocity.z * 10
	else:
		airborne_time += delta
	
		
func handle_sprint(): 
	if Input.is_action_pressed("sprint"):
		sprint_multiplier = 2
	else:
		sprint_multiplier = 1

var root_motion: Transform3D       = Transform3D()
var input_motion: Vector2          = Vector2()
var animation_tree_motion: Vector2 = Vector2()
var orientation: Transform3D = Transform3D() # not just used here, side affect in other methods
var sprint_multiplier: int = 1;
func apply_input_to_character(delta: float):
	input_motion = input_motion.lerp(player_input.motion, MOTION_INTERPOLATE_SPEED * delta)
	update_animation_tree_root_motion(input_motion)

	velocity += gravity * delta
	if is_on_floor():
		root_motion = Transform3D(animation_tree.get_root_motion_rotation(), animation_tree.get_root_motion_position())
		orientation *= root_motion
		var horizontal_velocity: Vector3 = orientation.origin / delta
		velocity.x = horizontal_velocity.x * sprint_multiplier
		velocity.z = horizontal_velocity.z * sprint_multiplier

	orientation.origin = Vector3() # Clear accumulated root motion displacement (was applied to speed).
	orientation = orientation.orthonormalized() # Orthonormalize orientation.

	player_model.global_transform.basis = orientation.basis



	
func animate_player():
	if is_on_floor():
		if is_landing():
			land.rpc()
		elif player_input.jumping:
			jump.rpc()
		elif player_input.aiming:
			animate(ANIMATIONS.STRAFE)
		else:
			animate(ANIMATIONS.WALK)
	else:
		if (velocity.y > 0):
			animate(ANIMATIONS.JUMP_UP)
		else:
			animate(ANIMATIONS.JUMP_DOWN)

func is_landing() -> bool:
	return is_on_floor() and airborne_time > MIN_AIR_TIME_FOR_LANDING_ANIMATION


func update_animation_tree_root_motion(input: Vector2):
	animation_tree_motion = input	
	
func rotate_character_with_independent_camera(delta: float):
	var camera_basis : Basis = player_input.get_camera_rotation_basis()
	var camera_z := camera_basis.z
	var camera_x := camera_basis.x

	camera_z.y = 0
	camera_z = camera_z.normalized()
	camera_x.y = 0
	camera_x = camera_x.normalized()
	var walk_target = camera_x * input_motion.x + camera_z * input_motion.y
	if walk_target.length() > 0.001:
		var current_basis = orientation.basis.get_rotation_quaternion()
		var walk_target_basis = Transform3D().looking_at(walk_target, Vector3.UP).basis.get_rotation_quaternion()
		orientation.basis = get_basis_for_transform(current_basis, walk_target_basis, delta)

		
func rotate_character_with_locked_camera(delta: float):
	var current_basis = orientation.basis.get_rotation_quaternion()
	var input_basis = player_input.get_camera_base_quaternion()
	orientation.basis = get_basis_for_transform(current_basis, input_basis, delta)


func get_basis_for_transform(from: Quaternion, to: Quaternion, delta: float) -> Basis:
	return Basis(from.slerp(to, delta * ROTATION_INTERPOLATE_SPEED))


func handle_shoot():
	if player_input.aiming:
		if player_input.shooting and fire_cooldown.time_left == 0:
			shoot_bullet()
	
		
func shoot_bullet():
	var shoot_origin = shoot_from.global_transform.origin
	var shoot_dir = (player_input.shoot_target - shoot_origin).normalized()

	var bullet = preload("res://src/player/bullet/bullet.tscn").instantiate()
	bullet.inherited_momentum = self.velocity
	get_parent().add_child(bullet, true)
	bullet.global_transform.origin = shoot_origin
	# If we don't rotate the bullets there is no useful way to control the particles ..
	bullet.look_at(shoot_origin + shoot_dir, Vector3.UP)
	bullet.add_collision_exception_with(self)
	shoot.rpc()

var is_grappled: bool          = false
var grapple_rest_length: float = 0
var grapple_extension: float   = 0
var last_grapple_extension: float   = 0
var pull_vector: Vector3
var tension_force: Vector3
var grapple_target: Vector3
var mesh: ImmediateMesh = ImmediateMesh.new()
func impart_velocity_from_grapple(delta: float) -> void:
	if(is_grappled):
		pull_vector = get_grapple_path().normalized()
		last_grapple_extension = grapple_extension
		grapple_extension = get_grapple_path().length() - grapple_rest_length
		line(position, grapple_target,delta)
		if(grapple_extension > 0 && grapple_extension > last_grapple_extension):
			tension_force = get_grapple_path() * (get_gravity().length()/get_grapple_path().length())
			tension_force = tension_force * (1 + sin(pull_vector.angle_to(get_gravity())))
			tension_force.y *= grapple_extension
			velocity += tension_force * delta

	if Input.is_action_just_pressed("grapple"):
		var origin = position + player_input.camera_camera.project_ray_normal(get_viewport().get_mouse_position()) 
		var end = position + player_input.camera_camera.project_ray_normal(get_viewport().get_mouse_position()) * 1000	
		var grapple_target_maybe = get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(origin, end))
		if grapple_target_maybe.has("position"):
			grapple_target = grapple_target_maybe["position"]
			grapple_rest_length = get_grapple_path().length()
			is_grappled = true

	if Input.is_action_just_released("grapple"):
		is_grappled = false
		
		
func get_grapple_path() -> Vector3:	
	return grapple_target-position


func line(pos1: Vector3, pos2: Vector3, persist_ms: float = 0):
	var mesh_instance := MeshInstance3D.new()
	var immediate_mesh := ImmediateMesh.new()
	var material := ORMMaterial3D.new()

	mesh_instance.mesh = immediate_mesh
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	immediate_mesh.surface_add_vertex(pos1)
	immediate_mesh.surface_add_vertex(pos2)
	immediate_mesh.surface_end()

	#get_tree().get_root().add_child(mesh_instance)

	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return await final_cleanup(mesh_instance, persist_ms)


func final_cleanup(mesh_instance: MeshInstance3D, persist_ms: float):
	get_tree().get_root().add_child(mesh_instance)
	if persist_ms == 1:
		await get_tree().physics_frame
		mesh_instance.queue_free()
	elif persist_ms > 0:
		await get_tree().create_timer(persist_ms).timeout
		mesh_instance.queue_free()
	else:
		return mesh_instance
	

func animate(anim: int):
	current_animation = anim

	if anim == ANIMATIONS.JUMP_UP:
		animation_tree["parameters/state/transition_request"] = "jump_up"

	elif anim == ANIMATIONS.JUMP_DOWN:
		animation_tree["parameters/state/transition_request"] = "jump_down"

	elif anim == ANIMATIONS.STRAFE:
		animation_tree["parameters/state/transition_request"] = "strafe"
		# Change aim according to camera rotation.
		animation_tree["parameters/aim/add_amount"] = player_input.get_aim_rotation()
		# The animation's forward/backward axis is reversed.
		animation_tree["parameters/strafe/blend_position"] = Vector2(animation_tree_motion.x, -animation_tree_motion.y)

	elif anim == ANIMATIONS.WALK:
		# Aim to zero (no aiming while walking).
		animation_tree["parameters/aim/add_amount"] = 0
		# Change state to walk.
		animation_tree["parameters/state/transition_request"] = "walk"
		# Blend position for walk speed based checked motion.
		animation_tree["parameters/walk/blend_position"] = Vector2(animation_tree_motion.length(), 0)

	
@rpc("call_local")
func jump():
	animate(ANIMATIONS.JUMP_UP)
	sound_effect_jump.play()


@rpc("call_local")
func land():
	animate(ANIMATIONS.JUMP_DOWN)
	sound_effect_land.play()


@rpc("call_local")
func shoot():
	var shoot_particle = $PlayerModel/Robot_Skeleton/Skeleton3D/GunBone/ShootFrom/ShootParticle
	shoot_particle.restart()
	shoot_particle.emitting = true
	var muzzle_particle = $PlayerModel/Robot_Skeleton/Skeleton3D/GunBone/ShootFrom/MuzzleFlash
	muzzle_particle.restart()
	muzzle_particle.emitting = true
	fire_cooldown.start()
	sound_effect_shoot.play()
	add_camera_shake_trauma(0.35)


@rpc("call_local")
func hit():
	add_camera_shake_trauma(.75)


@rpc("call_local")
func add_camera_shake_trauma(amount):
	player_input.camera_camera.add_trauma(amount)
