extends RigidBody3D
## Hand grenade (G). Bounces off the world and explodes after FUSE seconds.
## Online, the thrower's copy reports where it exploded and the server deals the
## damage; other clients fly a copy and wait for the server's "boom". Offline,
## the blast damages training dummies locally.
signal exploded(grenade_id: String, at: Vector3)

const HitboxScript = preload("res://scripts/net/hitbox.gd")
const FUSE := 2.6
const RADIUS := 7.0 # keep in sync with GRENADE_RADIUS in src/godot-match.js
const MAX_DAMAGE := 100.0
const THROW_SPEED := 17.0

var grenade_id := ""
var live := true # explodes on its own fuse (thrower / offline); remote copies wait for the server
var offline_damage := false
var _time := 0.0
var _done := false
static var _boom_sound: AudioStreamWAV

func _ready() -> void:
	collision_layer = 0
	collision_mask = HitboxScript.LAYER_WORLD
	mass = 0.4
	continuous_cd = true
	angular_damp = 1.5
	var bounce := PhysicsMaterial.new()
	bounce.bounce = 0.35
	bounce.friction = 0.9
	physics_material_override = bounce
	# Contatos para a resistência ao rolar (_integrate_forces).
	contact_monitor = true
	max_contacts_reported = 2
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.07
	shape.shape = sphere
	add_child(shape)
	var body := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.065
	mesh.height = 0.15
	body.mesh = mesh
	var olive := StandardMaterial3D.new()
	olive.albedo_color = Color("#4a5a35")
	olive.roughness = 0.7
	body.material_override = olive
	add_child(body)
	var lever := MeshInstance3D.new()
	var lever_mesh := BoxMesh.new()
	lever_mesh.size = Vector3(0.025, 0.09, 0.02)
	lever.mesh = lever_mesh
	lever.position = Vector3(0.05, 0.05, 0)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color("#9aa0a4")
	steel.metallic = 0.6
	lever.material_override = steel
	add_child(lever)

## Throw from `origin` along `direction`, adding the thrower's own velocity.
static func throw_velocity(direction: Vector3, carrier_velocity: Vector3) -> Vector3:
	return direction.normalized() * THROW_SPEED + Vector3.UP * 3.0 + carrier_velocity * 0.5

## Aim preview: simulates the throw (gravity, damping, bounces against the world)
## until the fuse ends. Returns {"points": PackedVector3Array, "first_hit": Vector3,
## "has_hit": bool, "end": Vector3, "end_normal": Vector3}. It approximates the
## rigid body, so after bounces the real grenade can land slightly elsewhere.
static func predict_path(space: PhysicsDirectSpaceState3D, origin: Vector3, start_velocity: Vector3, exclude: Array[RID] = []) -> Dictionary:
	const STEP := 1.0 / 60.0
	const BALL := 0.07
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var damp := float(ProjectSettings.get_setting("physics/3d/default_linear_damp", 0.1))
	var points := PackedVector3Array([origin])
	var pos := origin
	var v := start_velocity
	var first_hit := Vector3.ZERO
	var has_hit := false
	var end_normal := Vector3.UP
	var query := PhysicsRayQueryParameters3D.new()
	query.collision_mask = HitboxScript.LAYER_WORLD
	query.exclude = exclude
	var steps := int(ceil(FUSE / STEP))
	for i in steps:
		v.y -= gravity * STEP
		v *= maxf(0.0, 1.0 - damp * STEP)
		var target := pos + v * STEP
		query.from = pos
		query.to = target
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			pos = target
		else:
			var normal: Vector3 = hit["normal"]
			pos = hit["position"] + normal * BALL
			if not has_hit:
				has_hit = true
				first_hit = hit["position"]
			end_normal = normal
			var into := v.dot(normal)
			if into < 0.0:
				var normal_part := normal * into
				var tangent := v - normal_part
				if absf(into) > 1.5:
					v = tangent * 0.7 - normal_part * 0.35 # impact: bounce 0.35, friction eats part of the slide
				else:
					v = tangent * 0.97 # resting contact: rolls and slows down
			if v.length() < 0.4:
				v = Vector3.ZERO # settled
		points.append(pos)
	return {"points": points, "first_hit": first_hit, "has_hit": has_hit, "end": pos, "end_normal": end_normal}

## Resistência ao rolar, igual à de predict_path (×0,97 por quadro encostada,
## parada abaixo de 0,4 m/s): sem isso a esfera rola metros num chão liso
## (o campo de treino) e explode longe do círculo previsto.
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if state.get_contact_count() == 0:
		return
	var keep := pow(0.97, state.step * 60.0)
	state.linear_velocity *= keep
	state.angular_velocity *= keep
	if state.linear_velocity.length() < 0.4:
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO

func _physics_process(delta: float) -> void:
	_time += delta
	if live and _time >= FUSE:
		explode(global_position)
	elif not live and _time > 8.0:
		queue_free() # the server never confirmed it

func explode(at: Vector3) -> void:
	if _done:
		return
	_done = true
	spawn_explosion(get_parent(), at)
	if offline_damage:
		_damage_dummies(at)
	exploded.emit(grenade_id, at)
	queue_free()

## Offline: training dummies take the same falloff damage as online players.
func _damage_dummies(at: Vector3) -> void:
	for dummy in get_tree().get_nodes_in_group("training_dummy"):
		var distance: float = (dummy.global_position + Vector3(0, 1.0, 0)).distance_to(at)
		if distance < RADIUS:
			dummy.call("explosion_hit", MAX_DAMAGE * (1.0 - distance / RADIUS), at)

## Flash, fireball, smoke and a low boom at `at` (used online for every blast).
static func spawn_explosion(parent: Node, at: Vector3) -> void:
	if parent == null:
		return
	var root := Node3D.new()
	root.name = "Explosion"
	parent.add_child(root)
	root.global_position = at
	var light := OmniLight3D.new()
	light.light_color = Color("#ffb45a")
	light.light_energy = 6.0
	light.omni_range = 9.0
	root.add_child(light)
	var fire := CPUParticles3D.new()
	fire.one_shot = true
	fire.amount = 40
	fire.lifetime = 0.45
	fire.explosiveness = 1.0
	fire.direction = Vector3.UP
	fire.spread = 180.0
	fire.initial_velocity_min = 3.0
	fire.initial_velocity_max = 8.0
	fire.gravity = Vector3(0, -4, 0)
	fire.scale_amount_min = 1.5
	fire.scale_amount_max = 3.0
	var flame := SphereMesh.new()
	flame.radius = 0.12
	flame.height = 0.24
	flame.radial_segments = 6
	flame.rings = 3
	var flame_material := StandardMaterial3D.new()
	flame_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_material.albedo_color = Color("#ffa040")
	flame.material = flame_material
	fire.mesh = flame
	root.add_child(fire)
	fire.emitting = true
	var smoke := CPUParticles3D.new()
	smoke.one_shot = true
	smoke.amount = 24
	smoke.lifetime = 1.6
	smoke.explosiveness = 0.9
	smoke.direction = Vector3.UP
	smoke.spread = 60.0
	smoke.initial_velocity_min = 1.0
	smoke.initial_velocity_max = 3.0
	smoke.gravity = Vector3(0, 0.6, 0)
	smoke.scale_amount_min = 2.0
	smoke.scale_amount_max = 4.0
	var puff := SphereMesh.new()
	puff.radius = 0.2
	puff.height = 0.4
	puff.radial_segments = 6
	puff.rings = 3
	var smoke_material := StandardMaterial3D.new()
	smoke_material.albedo_color = Color(0.25, 0.24, 0.22, 0.65)
	smoke_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff.material = smoke_material
	smoke.mesh = puff
	root.add_child(smoke)
	smoke.emitting = true
	var sound := AudioStreamPlayer3D.new()
	sound.stream = _explosion_sound()
	sound.unit_size = 14.0
	sound.max_distance = 120.0
	sound.volume_db = 4.0
	root.add_child(sound)
	sound.play()
	var tween := root.create_tween()
	tween.tween_property(light, "light_energy", 0.0, 0.35)
	tween.tween_interval(1.8)
	tween.tween_callback(root.queue_free)

## Low rumbling noise burst, generated once in memory (no external audio file).
static func _explosion_sound() -> AudioStreamWAV:
	if _boom_sound != null:
		return _boom_sound
	var rate := 22050
	var count := int(rate * 1.1)
	var data := PackedByteArray()
	data.resize(count * 2)
	var smooth := 0.0
	for i in count:
		var t := float(i) / rate
		var envelope := exp(-t * 4.5) * minf(1.0, t * 200.0)
		smooth = lerpf(smooth, randf_range(-1.0, 1.0), 0.08) # low-passed noise
		var sample := clampf((smooth * 2.6 + sin(t * TAU * 48.0) * 0.5 * exp(-t * 6.0)) * envelope, -1.0, 1.0)
		data.encode_s16(i * 2, int(sample * 32000.0))
	var wave := AudioStreamWAV.new()
	wave.format = AudioStreamWAV.FORMAT_16_BITS
	wave.mix_rate = rate
	wave.data = data
	_boom_sound = wave
	return wave
