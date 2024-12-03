class_name Player
extends CharacterBody3D

enum ANIMATIONS {JUMP_UP, JUMP_DOWN, STRAFE, WALK}

const DIRECTION_INTERPOLATE_SPEED = 1
const MOTION_INTERPOLATE_SPEED = 10
const ROTATION_INTERPOLATE_SPEED = 10

const MIN_AIRBORNE_TIME = 0.1
const MIN_AIR_TIME_FOR_LANDING_ANIMATION = 0.5
const JUMP_SPEED = 5


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

func _ready():
	orientation = player_model.global_transform
	orientation.origin = Vector3()


func _physics_process(delta: float):
	apply_input(delta)

var airborne_time: float     = 100
var orientation: Transform3D = Transform3D()
var root_motion: Transform3D = Transform3D()
var motion: Vector2          = Vector2()
func apply_input(delta: float):
	animate_player()
	motion = motion.lerp(player_input.motion, MOTION_INTERPOLATE_SPEED * delta)

	if player_input.aiming:
		if player_input.shooting and fire_cooldown.time_left == 0:
			shoot_bullet()
		
	if player_input.aiming:
		rotate_character_with_locked_camera(delta)
	else:
		rotate_character_with_independent_camera(delta)

	if is_on_floor():
		root_motion = Transform3D(animation_tree.get_root_motion_rotation(), animation_tree.get_root_motion_position())
		if airborne_time > MIN_AIR_TIME_FOR_LANDING_ANIMATION:
			land.rpc()
			player_input.jumping = false
		elif player_input.jumping:
			velocity.y = JUMP_SPEED
			jump.rpc()
		airborne_time = 0
	else:
		airborne_time += delta

	# Apply root motion to orientation.
	orientation *= root_motion

	# note to self; this function is still too long and I think most of the below should be pulled into another method
	#this function is also doing too much, trying to handle move/anim states and motion, already pulled a lot out

	var horizontal_velocity = orientation.origin / delta
	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z
	velocity += gravity * delta
	move_and_slide()

	orientation.origin = Vector3() # Clear accumulated root motion displacement (was applied to speed).
	orientation = orientation.orthonormalized() # Orthonormalize orientation.

	player_model.global_transform.basis = orientation.basis

func animate_player():
	if is_on_floor():
		if airborne_time > MIN_AIR_TIME_FOR_LANDING_ANIMATION:
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
	
func rotate_character_with_independent_camera(delta: float):
	var camera_basis : Basis = player_input.get_camera_rotation_basis()
	var camera_z := camera_basis.z
	var camera_x := camera_basis.x

	camera_z.y = 0
	camera_z = camera_z.normalized()
	camera_x.y = 0
	camera_x = camera_x.normalized()
	var walk_target = camera_x * motion.x + camera_z * motion.y
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

func shoot_bullet():
	var shoot_origin = shoot_from.global_transform.origin
	var shoot_dir = (player_input.shoot_target - shoot_origin).normalized()

	var bullet = preload("res://src/player/bullet/bullet.tscn").instantiate()
	get_parent().add_child(bullet, true)
	bullet.global_transform.origin = shoot_origin
	# If we don't rotate the bullets there is no useful way to control the particles ..
	bullet.look_at(shoot_origin + shoot_dir, Vector3.UP)
	bullet.add_collision_exception_with(self)
	shoot.rpc()
	
	
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
		animation_tree["parameters/strafe/blend_position"] = Vector2(motion.x, -motion.y)

	elif anim == ANIMATIONS.WALK:
		# Aim to zero (no aiming while walking).
		animation_tree["parameters/aim/add_amount"] = 0
		# Change state to walk.
		animation_tree["parameters/state/transition_request"] = "walk"
		# Blend position for walk speed based checked motion.
		animation_tree["parameters/walk/blend_position"] = Vector2(motion.length(), 0)

	
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
