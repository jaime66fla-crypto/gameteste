extends "res://scripts/net/hitbox.gd"
## Casca de acerto do zumbi: uma cápsula só, presa ao corpo (não aos ossos).
## Mover 12 corpos de física por zumbi a cada quadro custava caro; agora o tiro
## acerta a casca e `resolve_ray` descobre, pela conta, qual parte do corpo
## (cabeça, tronco, braço, perna) o raio atravessa. Se não passa por nenhuma,
## o tiro segue (quem atira ignora a casca e lança o raio de novo).

## {zone, position, normal} da parte atingida, ou {} se o raio passa entre os braços/pernas.
func resolve_ray(origin: Vector3, direction: Vector3) -> Dictionary:
	if actor == null:
		return {}
	var avatar = actor.get("visual")
	if avatar == null or not avatar.has_method("resolve_ray"):
		return {"zone": zone, "position": global_position, "normal": -direction}
	var result: Dictionary = avatar.call("resolve_ray", origin, direction)
	if not result.is_empty():
		zone = str(result["zone"])
	return result
