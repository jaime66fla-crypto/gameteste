extends SceneTree
## Salva o ciclo de corrida que vem embutido no FBX do Ch31 ("mixamo_com") como
## clipe próprio, para outros personagens Mixamo usarem a mesma corrida.
## Também imprime a altura de repouso do quadril (Hips), usada pelo adaptador
## para escalar o sobe-e-desce do quadril em esqueletos de outro tamanho.
## godot --headless --path godot --script res://tools/characters/export_shared_run.gd
const SOURCE := "res://assets/personagens/downloaded/avatar.fbx"
const OUT := "res://assets/personagens/downloaded/movements/run_in_place.tres"

func _initialize() -> void:
	var model := (load(SOURCE) as PackedScene).instantiate() as Node3D
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if skeleton == null or player == null or not player.has_animation("mixamo_com"):
		printerr("EXPORT RUN: modelo sem esqueleto ou sem mixamo_com")
		model.free()
		quit(1)
		return
	var hips := skeleton.find_bone("mixamorig9_Hips")
	print("skeleton path from player root: ", player.get_node(player.root_node).get_path_to(skeleton))
	print("hips rest: ", skeleton.get_bone_rest(hips).origin)
	print("skeleton global scale: ", skeleton.global_transform.basis.get_scale() if skeleton.is_inside_tree() else skeleton.transform.basis.get_scale())
	var clip := player.get_animation("mixamo_com").duplicate(true) as Animation
	clip.loop_mode = Animation.LOOP_LINEAR
	clip.set_meta("source", "Ch31 avatar.fbx mixamo_com")
	var err := ResourceSaver.save(clip, OUT)
	print("EXPORT RUN: ", "PASS" if err == OK else "FAIL %d" % err, "  tracks=", clip.get_track_count(), " length=", clip.length)
	model.free()
	quit(0 if err == OK else 1)
