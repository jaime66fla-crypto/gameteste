extends RefCounted
## Raio de golpe corpo a corpo (soco, arma branca) usado no Combate, na
## Sobrevivência e na arena do treino.
const HitboxScript = preload("res://scripts/net/hitbox.gd")

## Sai da câmera, pela mira: a câmera fica no ombro, e um raio do peito na
## direção da câmera passava ao lado do alvo de perto. Só vale se o ponto
## atingido estiver a até `reach` (no chão) do jogador. Colado num alvo largo
## (zumbi brute) a câmera pode estar dentro da casca de acerto: também vale.
static func ray(who: CharacterBody3D, camera: Camera3D, reach: float) -> Dictionary:
	var forward := -camera.global_basis.z
	var from := camera.global_position
	var length := from.distance_to(who.global_position + Vector3(0, 1.35, 0)) + reach
	var query := PhysicsRayQueryParameters3D.create(from, from + forward * length, HitboxScript.SHOT_MASK)
	query.exclude = [who.get_rid()]
	query.hit_from_inside = true
	var hit := who.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {}
	var p: Vector3 = hit["position"]
	if Vector2(p.x - who.global_position.x, p.z - who.global_position.z).length() > reach + 0.35:
		return {}
	return hit
