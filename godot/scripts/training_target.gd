extends StaticBody3D
## Placa de aço do estande do treino offline: balança e pisca quando leva
## tiro (player.gd chama take_damage no colisor) e conta os acertos.
const TrainingGround = preload("res://scripts/training_ground.gd")

var size := Vector2(0.6, 0.6)
var title := ""
var sound_fx: Node # o do jogador, para o "tim" do acerto
var hits := 0
var _swing := 0.0
var _flash := 0.0
var _mesh: MeshInstance3D
var _material: StandardMaterial3D
var _label: Label3D

func _ready() -> void:
	add_to_group("training_target")
	_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(size.x, size.y, 0.05)
	_mesh.mesh = box
	_material = TrainingGround.material("target").duplicate()
	_mesh.material_override = _material
	add_child(_mesh)
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = box.size
	shape.shape = bs
	add_child(shape)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 30
	_label.outline_size = 4
	_label.visibility_range_end = 32.0
	_label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_label.pixel_size = 0.005
	_label.modulate = Color("#ffe08a")
	_label.position = Vector3(0, size.y * 0.5 + 0.45, 0)
	add_child(_label)
	_update_label()

func take_damage(_amount: float) -> void:
	hits += 1
	_swing = 1.0
	_flash = 1.0
	_update_label()
	if sound_fx != null and sound_fx.has_method("hit_confirm"):
		sound_fx.call("hit_confirm", false)

func _process(delta: float) -> void:
	if _swing <= 0.0 and _flash <= 0.0:
		return
	_swing = maxf(0.0, _swing - delta * 1.6)
	_flash = maxf(0.0, _flash - delta * 4.0)
	# Balança para trás e volta (a placa pende do suporte).
	_mesh.rotation.x = -sin(_swing * PI * 3.0) * 0.35 * _swing
	_material.albedo_color = Color.WHITE.lerp(Color("#fff2a8"), _flash)
	_material.emission_enabled = _flash > 0.0
	_material.emission = Color("#ffb347") * _flash

func _update_label() -> void:
	_label.text = "%s\nacertos: %d" % [title, hits] if not title.is_empty() else "acertos: %d" % hits
