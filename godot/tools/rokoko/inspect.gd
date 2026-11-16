extends SceneTree
func _initialize() -> void:
    call_deferred("_run")
func _run() -> void:
    var report := []
    var base := "res://assets/personagens/jaime/animacoes/rokoko/"
    for file in DirAccess.get_files_at(base):
        if not file.ends_with(".fbx"): continue
        var model = load(base + file).instantiate()
        root.add_child(model)
        var sk = model.find_child("Skeleton3D", true, false) as Skeleton3D
        var ap = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
        var item := {"file": file, "bones": [], "animations": []}
        for b in sk.get_bone_count():
            item.bones.append({"name": sk.get_bone_name(b), "parent":sk.get_bone_parent(b), "rest": str(sk.get_bone_global_rest(b))})
        for clip in ap.get_animation_list():
            var a = ap.get_animation(clip)
            var tracks := []
            for t in a.get_track_count():
                if a.track_get_type(t) == Animation.TYPE_POSITION_3D:
                    tracks.append({"path": str(a.track_get_path(t)), "first": str(a.track_get_key_value(t,0)), "last": str(a.track_get_key_value(t,a.track_get_key_count(t)-1))})
            item.animations.append({"name":clip,"length":a.length,"tracks":tracks})
        report.append(item)
        print(file, " bones=",sk.get_bone_count(), " clips=",item.animations)
        model.free()
    FileAccess.open("res://tools/rokoko/inspection.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
    quit()
