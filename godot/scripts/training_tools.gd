extends Node3D
## Treino offline: estação de ferramentas ao lado da arena do zumbi, para testar
## as animações. Um suporte com todas as ferramentas e armas brancas da
## Sobrevivência, uma árvore e uma pedra.
##  - E no suporte: pega a próxima ferramenta (a última opção larga);
##  - E perto da árvore: corta (machadada lateral) por alguns segundos;
##  - E perto da pedra: quebra (picareta de cima para baixo; pé de cabra etc. golpe baixo);
##  - clique esquerdo: golpe de ataque da ferramenta (training_arena._melee).
## A arma de fogo fica guardada enquanto houver ferramenta na mão.
const NatureModel = preload("res://scripts/survival/nature_model.gd")
const ToolModel = preload("res://scripts/weapons/tool_model.gd")
const SurvivalData = preload("res://scripts/survival/survival_data.gd")
const TrainingGround = preload("res://scripts/training_ground.gd")
const BowController = preload("res://scripts/weapons/bow_controller.gd")
const BowVisual = preload("res://scripts/weapons/bow_visual.gd")
const BOW_RACK := Vector3(44.4, 0, 29.4)
# Ao leste da arena do zumbi (training_arena.CENTER = (30, 0, 32)).
const CENTER := Vector3(41, 0, 32)
const RACK := CENTER + Vector3(0, 0, -2.6)
const TREE := CENTER + Vector3(-2.6, 0, 1.6)
const ROCK := CENTER + Vector3(2.6, 0, 1.6)
const REACH := 2.2
const WORK_TIME := 4.0
const TOOLS := ["stone_axe", "iron_axe", "stone_pick", "iron_pick", "stone_knife", "iron_knife", "machete", "wood_spear", "club", "nail_bat"]

var player: CharacterBody3D
var _previous_interact: Callable
var _rack_models: Dictionary = {} # ferramenta -> modelo no suporte
var _rack_label: Label3D
var _working := false
var _bow_controller: Node
var _bow_rack_model: Node3D
var _bow_label: Label3D

func setup(p: CharacterBody3D) -> void:
	player = p

func _ready() -> void:
	name = "TrainingTools"
	_build_rack()
	_build_tree()
	_build_rock()
	_build_bow_station()
	_label("ÁRVORE\n[E] cortar", TREE + Vector3(0, 2.4, 0))
	_label("PEDRA\n[E] quebrar", ROCK + Vector3(0, 1.6, 0))
	_label("FERRAMENTAS — teste das animações\nclique esquerdo: golpe de ataque", CENTER + Vector3(0, 3.0, -3.4), 34)
	if player != null:
		_previous_interact = player.get("interact_handler")
		player.set("interact_handler", _interact)
		_bow_controller = player.get("bow_controller")
		if _bow_controller == null:
			_bow_controller = BowController.new()
			player.add_child(_bow_controller)
			_bow_controller.call("setup", player)

func _build_bow_station() -> void:
	var stand := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.7, 0.9, 0.55)
	stand.mesh = box
	stand.material_override = TrainingGround.material("orange_grid")
	stand.position = BOW_RACK + Vector3(0, 0.45, 0)
	add_child(stand)
	_bow_rack_model = BowVisual.new()
	_bow_rack_model.position = BOW_RACK + Vector3(0, 1.35, 0)
	add_child(_bow_rack_model)
	_bow_label = _label("ARCO E FLECHA\n[E] pegar\nSegure o esquerdo: mirar\nSolte: disparar", BOW_RACK + Vector3(0, 2.5, 0), 27)

func _label(text: String, pos: Vector3, size: int = 28) -> Label3D:
	var tag := Label3D.new()
	tag.text = text
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.font_size = size
	tag.outline_size = 8
	tag.pixel_size = 0.004
	tag.position = pos
	add_child(tag)
	return tag

func _solid(pos: Vector3, shape: Shape3D) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	add_child(body)

## Mesa comprida com as ferramentas deitadas lado a lado, lâmina para cima.
func _build_rack() -> void:
	var width := 4.4
	var top := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(width, 0.08, 0.7)
	top.mesh = box
	top.position = RACK + Vector3(0, 0.82, 0)
	top.material_override = TrainingGround.material("orange_grid")
	add_child(top)
	for side in [-1.0, 1.0]:
		var leg := MeshInstance3D.new()
		var leg_box := BoxMesh.new()
		leg_box.size = Vector3(0.08, 0.8, 0.6)
		leg.mesh = leg_box
		leg.position = RACK + Vector3(side * (width * 0.5 - 0.1), 0.4, 0)
		leg.material_override = TrainingGround.material("dark_grid")
		add_child(leg)
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, 0.86, 0.7)
	_solid(RACK + Vector3(0, 0.43, 0), shape)
	for i in TOOLS.size():
		var tool: String = TOOLS[i]
		var model := ToolModel.build(tool)
		# Deitada na mesa: base do cabo na borda de trás (sul), cabeça para quem chega
		# pelo norte (-Z), lâmina virada para cima.
		model.basis = Basis(Vector3.RIGHT, -PI * 0.5) * Basis(Vector3.UP, PI)
		model.position = RACK + Vector3(-width * 0.5 + 0.3 + i * (width - 0.6) / (TOOLS.size() - 1), 0.88, 0.3)
		add_child(model)
		_rack_models[tool] = model
	_rack_label = _label("", RACK + Vector3(0, 1.45, 0), 26)
	_refresh_rack()

func _build_tree() -> void:
	var tree := MeshInstance3D.new()
	tree.mesh = NatureModel.mesh("oak_a")
	tree.position = TREE
	add_child(tree)
	var trunk := CylinderShape3D.new()
	trunk.radius = 0.32
	trunk.height = 4.0
	_solid(TREE + Vector3(0, 2.0, 0), trunk)

func _build_rock() -> void:
	var rock := MeshInstance3D.new()
	rock.mesh = NatureModel.mesh("rock")
	rock.scale = Vector3.ONE * 0.9
	rock.position = ROCK
	add_child(rock)
	var shape := SphereShape3D.new()
	shape.radius = 0.5
	_solid(ROCK + Vector3(0, 0.15, 0), shape)

func _in_hand() -> String:
	return str(player.get("melee_weapon")) if player != null else ""

func _refresh_rack() -> void:
	var held := _in_hand()
	for tool in _rack_models:
		(_rack_models[tool] as Node3D).visible = tool != held
	var idx := TOOLS.find(held)
	var next: String = TOOLS[(idx + 1) % TOOLS.size()] if idx < TOOLS.size() - 1 else ""
	var now := "na mão: " + (SurvivalData.item_name(held) if held in TOOLS else "nada")
	var after := ("[E] pegar " + SurvivalData.item_name(next)) if not next.is_empty() else "[E] devolver"
	_rack_label.text = "%s\n%s" % [now, after]

func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _process(_delta: float) -> void:
	if player == null:
		return
	if _bow_controller != null:
		var holding_bow := bool(_bow_controller.get("equipped"))
		_bow_rack_model.visible = not holding_bow
		_bow_label.text = "ARCO E FLECHA\n[E] devolver" if holding_bow else "ARCO E FLECHA\n[E] pegar\nSegure o esquerdo: mirar\nSolte: disparar"
	if _working and float(player.get("channel_left")) <= 0.0:
		_stop_work()
	if _rack_label != null and Engine.get_process_frames() % 10 == 0:
		_refresh_rack()

## E: suporte (troca de ferramenta), árvore (corta) ou pedra (quebra); senão
## passa para a arena (bastão longo).
func _interact() -> bool:
	if player == null:
		return false
	var pos := player.global_position
	if _flat(pos, BOW_RACK) < REACH:
		if bool(_bow_controller.get("equipped")):
			_bow_controller.call("unequip")
		else:
			_bow_controller.call("equip")
		return true
	if _flat(pos, RACK) < REACH:
		_next_tool()
		return true
	if _flat(pos, TREE) < REACH + 0.3:
		_work("chop", TREE, 1.15, "CORTANDO")
		return true
	if _flat(pos, ROCK) < REACH + 0.3:
		_work("pry", ROCK, 1.3, "QUEBRANDO")
		return true
	return bool(_previous_interact.call()) if _previous_interact.is_valid() else false

func _next_tool() -> void:
	if _bow_controller != null and bool(_bow_controller.get("equipped")):
		_bow_controller.call("unequip")
	var held := _in_hand()
	var idx := TOOLS.find(held)
	var next: String = TOOLS[idx + 1] if idx < TOOLS.size() - 1 else ""
	if idx < 0:
		next = TOOLS[0]
	if not next.is_empty() and not bool(player.get("weapon_holstered")):
		player.call("_toggle_weapon_holster") # o clique esquerdo passa a golpear com a ferramenta
	player.set("melee_weapon", next)
	_refresh_rack()

func _work(act: String, target: Vector3, distance: float, label: String) -> void:
	var tool := _in_hand()
	if tool.is_empty():
		_rack_label.text = "Pegue uma ferramenta no suporte [E]"
		return
	if not bool(player.call("start_channel", label, WORK_TIME, Callable())):
		return
	# Vira para o alvo e chega na distância do golpe (como na Sobrevivência).
	var to := target - player.global_position
	to.y = 0.0
	player.set("yaw", atan2(-to.x, -to.z))
	if player.has_method("face_aim"):
		player.call("face_aim", WORK_TIME)
	var spot := target - to.normalized() * distance
	spot.y = player.global_position.y
	create_tween().tween_property(player, "global_position", spot, 0.25)
	_set_action("", "")
	_set_action(act, tool)
	_working = true

func _stop_work() -> void:
	_working = false
	var tool := _in_hand()
	_set_action("", "")
	_set_action("hold" if not tool.is_empty() else "", tool)

func _set_action(act: String, tool: String) -> void:
	var avatar = player.get("humanoid_avatar")
	if avatar != null and avatar.has_method("set_action"):
		avatar.call("set_action", act, tool)
