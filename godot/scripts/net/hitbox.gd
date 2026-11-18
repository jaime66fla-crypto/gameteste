extends StaticBody3D
## One body-part hit volume, attached to a skeleton bone of a NetActor.
## Shots query only the world and these volumes (not the movement capsule),
## so damage follows the animated body and the zone sets the multiplier.

## Physics layers shared by the shooting code.
const LAYER_WORLD := 1
const LAYER_CHARACTERS := 2 # movement capsules: block walking, ignored by bullets
const LAYER_HITBOXES := 4
## Degraus de escada só para os pés (raio do IK): ninguém colide nem atira
## neles; o corpo anda na rampa invisível (parkour_district._stairs).
const LAYER_FOOT_PROBE := 8
const SHOT_MASK := LAYER_WORLD | LAYER_HITBOXES
## Damage multipliers per zone. Keep in sync with ZONE_MULTIPLIER in src/godot-match.js.
const MULTIPLIER := {"head": 2.0, "chest": 1.0, "pelvis": 0.9, "arm": 0.7, "leg": 0.7}

var actor: Node
var zone := "chest"

func _init() -> void:
	collision_layer = LAYER_HITBOXES
	collision_mask = 0

func take_hit(amount: float, point: Vector3, normal: Vector3, weapon_id: String) -> void:
	if actor != null:
		actor.call("receive_hit", zone, amount, point, normal, weapon_id)

## Fallback for callers that only know the damage amount.
func take_damage(amount: float) -> void:
	take_hit(amount, global_position, Vector3.UP, "")
