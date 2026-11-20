extends RefCounted
## Golpe corpo a corpo (soco, faca, arma branca) usado no Combate, na
## Sobrevivência e na arena do treino.
##
## Não usa a mira: arma branca não tem mira. O golpe sai do CORPO do
## personagem, para a frente dele (o lado para onde a câmera olha, que é para
## onde o golpe vira o corpo), e acerta o que estiver dentro do alcance da
## arma (`reach`, medido do centro do corpo). Olhar para cima/baixo não muda
## nada: uma esfera varre a altura do peito e, se não pegar nada, a da cintura
## (lobo, javali, zumbi rastejando). Parede no caminho segura o golpe.
const HitboxScript = preload("res://scripts/net/hitbox.gd")

const RADIUS := 0.35 # "largura" do golpe (o braço/arma não é uma linha fina)
const HEIGHTS := [1.25, 0.6] # peito e cintura, a partir dos pés

## Devolve {} ou {collider, position, normal, from, dir}. `from`/`dir` são a
## origem e a direção do golpe (para a casca do zumbi achar a parte do corpo).
static func sweep(who: CharacterBody3D, reach: float) -> Dictionary:
	var fwd := -who.global_basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.0001:
		return {}
	fwd = fwd.normalized()
	var space := who.get_world_3d().direct_space_state
	var exclude: Array[RID] = [who.get_rid()]
	# As próprias caixas de acerto do personagem não podem levar o golpe.
	for child in who.find_children("*", "StaticBody3D", true, false):
		exclude.append((child as StaticBody3D).get_rid())
	var shape := SphereShape3D.new()
	shape.radius = RADIUS
	for h in HEIGHTS:
		var from: Vector3 = who.global_position + Vector3(0.0, float(h), 0.0)
		var hit := _cast(space, shape, from, fwd, maxf(reach - RADIUS, 0.05), exclude)
		if not hit.is_empty():
			return hit
	return {}

static func _cast(space: PhysicsDirectSpaceState3D, shape: Shape3D, from: Vector3, dir: Vector3, length: float, exclude: Array[RID]) -> Dictionary:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = HitboxScript.SHOT_MASK
	q.exclude = exclude
	q.transform = Transform3D(Basis(), from)
	q.motion = dir * length
	var frac := space.cast_motion(q)
	if frac.is_empty() or frac[1] >= 1.0:
		return {}
	q.transform = Transform3D(Basis(), from + dir * length * frac[1])
	q.motion = Vector3.ZERO
	var info := space.get_rest_info(q)
	if info.is_empty():
		return {}
	var collider := instance_from_id(int(info["collider_id"]))
	if collider == null:
		return {}
	return {"collider": collider, "position": info["point"], "normal": info["normal"], "from": from, "dir": dir}
