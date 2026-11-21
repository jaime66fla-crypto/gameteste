extends Node3D
## Swept collision per physics step prevents tunnelling through thin cover.
const MODEL := preload("res://assets/weapons/bow/arrow.glb")
var shooter: Node3D
var velocity := Vector3.ZERO
var damage := 55.0
var stuck := false
var visual_only := false
var arrow_id := ""
var _life := 12.0

func _ready() -> void:
	name = "BowArrow"
	var model := MODEL.instantiate() as Node3D
	model.position.z = -0.85 # node origin is the swept tip; shaft stays behind
	add_child(model)

func launch(owner_player: Node3D, origin: Vector3, speed: Vector3, amount: float) -> void:
	shooter = owner_player
	global_position = origin
	velocity = speed
	damage = amount
	_orient()

func _orient() -> void:
	if velocity.length_squared() > 0.01:
		var forward := velocity.normalized()
		var up := Vector3.RIGHT if absf(forward.dot(Vector3.UP)) > 0.98 else Vector3.UP
		look_at(global_position - forward, up) # model points along +Z

func _physics_process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0 or not is_instance_valid(shooter):
		queue_free()
		return
	if stuck:
		return
	var next := global_position + velocity * delta + Vector3.DOWN * 4.9 * delta * delta
	var hit: Dictionary = {}
	if shooter.has_method("_shot_ray"):
		hit = shooter.call("_shot_ray", global_position, next)
	else:
		var query := PhysicsRayQueryParameters3D.create(global_position, next, 1)
		hit = get_world_3d().direct_space_state.intersect_ray(query)
	velocity += Vector3.DOWN * 9.8 * delta
	_orient()
	if hit.is_empty():
		global_position = next
		return
	global_position = hit["position"]
	stuck = true
	if visual_only:
		return
	var controller: Node = shooter.get("bow_controller")
	if is_instance_valid(controller):
		controller.set("last_hit_arrow_id", arrow_id)
	var target: Object = hit.get("collider")
	if target != null and target.has_method("take_hit"):
		target.call("take_hit", damage, global_position, hit["normal"], "bow")
	elif target != null and target.has_method("take_damage"):
		target.call("take_damage", damage)
