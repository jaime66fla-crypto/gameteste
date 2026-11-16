extends RefCounted
## Local integration component. No original WeaponProportions.gd was supplied/found.
## Profiles describe the actual Polyy meshes (visually inspected), never combat stats.
const BASE := "res://assets/weapons/polyy/models/"
const PROFILES := {
    "pistol": {"file":"compact_polymer_pistol.glb", "length":0.18, "yaw":-PI/2.0, "grip":Vector3(0.29,-0.17,0), "support":Vector3(-0.027,0.015,0.008), "right":0.027, "sight":Vector3(0.38,0.415,0)},
    "rifle": {"file":"modern_tactical_carbine.glb", "length":0.78, "yaw":PI/2.0, "grip":Vector3(-0.18,-0.14,0), "support":Vector3(-0.042,0.10,-0.22), "right":0.033, "sight":Vector3(-0.02,0.235,0)},
    "sniper": {"file":"bolt_action_sniper_rifle.glb", "length":1.10, "yaw":PI/2.0, "grip":Vector3(-0.24,-0.065,0), "support":Vector3(-0.035,0.035,-0.24), "right":0.032, "sight":Vector3(-0.08,0.125,0)},
    "shotgun": {"file":"pump_action_shotgun.glb", "length":0.95, "yaw":PI/2.0, "grip":Vector3(-0.25,-0.035,0), "support":Vector3(-0.035,0.065,-0.24), "right":0.030, "sight":Vector3(-0.12,0.10,0)},
    "smg": {"file":"compact_submachine_gun.glb", "length":0.55, "yaw":PI/2.0, "grip":Vector3(-0.26,-0.16,0), "support":Vector3(-0.032,0.025,-0.23), "right":0.030, "sight":Vector3(-0.21,0.22,0)}
}

static func create_model(id: String) -> Node3D:
    if not PROFILES.has(id):
        return null
    var path := BASE + str(PROFILES[id]["file"])
    var legacy_external := "res://assets/weapons/%s.glb" % id
    var yaw: float = PROFILES[id]["yaw"]
    if ResourceLoader.exists(legacy_external):
        path = legacy_external
        yaw = PI # Preserve the documented external-model convention.
    if not ResourceLoader.exists(path):
        return null
    var adapter := "res://scenes/weapons/polyy/%s.tscn" % id
    var packed := load(adapter if path.begins_with(BASE) and ResourceLoader.exists(adapter) else path) as PackedScene
    if packed == null:
        return null
    var model := packed.instantiate() as Node3D
    if model:
        model.name = "ImportedWeapon"
        model.rotation.y = yaw
        model.set_meta("source_path", path)
        model.set_meta("polyy", path.begins_with(BASE))
    return model

static func _points(node: Node, relative: Node3D, result: Array[Vector3]) -> void:
    if node is MeshInstance3D:
        var transform: Transform3D = relative.global_transform.affine_inverse() * node.global_transform
        for surface in range(node.mesh.get_surface_count()):
            var arrays: Array = node.mesh.surface_get_arrays(surface)
            for vertex in arrays[Mesh.ARRAY_VERTEX]:
                result.append(transform * vertex)
    for child in node.get_children():
        _points(child, relative, result)

static func apply(model: Node3D, id: String, imported: Node3D = null) -> bool:
    if not PROFILES.has(id):
        return false
    model.transform = Transform3D.IDENTITY
    var points: Array[Vector3] = []
    _points(model, model, points)
    if points.is_empty():
        return false
    var low := Vector3(INF,INF,INF)
    var high := Vector3(-INF,-INF,-INF)
    for point in points:
        low = low.min(point)
        high = high.max(point)
    var size := high-low
    if size.z < 0.0001:
        return false
    var parent_scale := model.get_parent_node_3d().global_basis.get_scale().y
    var uniform: float = PROFILES[id]["length"] / size.z / parent_scale
    var raw_grip := Vector3(0,-0.18,-0.21)
    var raw_sight := Vector3(0,0.15,-0.25)
    if imported:
        raw_grip = imported.transform * (PROFILES[id]["grip"] as Vector3)
        raw_sight = imported.transform * (PROFILES[id]["sight"] as Vector3)
    # Absolute transform from source geometry; never multiply the previous scale.
    model.scale = Vector3.ONE * uniform
    model.position = -raw_grip * uniform
    var tip := Vector3.ZERO
    var tip_count := 0
    var band := maxf(0.0002, size.z * 0.002)
    for point in points:
        if point.z <= low.z + band:
            tip += point
            tip_count += 1
    tip /= maxi(tip_count,1)
    _marker(model,"Muzzle",tip)
    _marker(model,"Sight",raw_sight)
    _marker(model,"Grip",raw_grip)
    # Contact points are in world metres around the centre of the real grip.
    var inverse := model.transform.affine_inverse()
    _marker(model,"RightGrip", inverse * (Vector3(float(PROFILES[id]["right"]),0,0)/parent_scale))
    _marker(model,"LeftGrip", inverse * ((PROFILES[id]["support"] as Vector3)/parent_scale))
    _marker(model,"ReloadGrip", inverse * (Vector3(-0.025,-0.09,-0.07)/parent_scale))
    model.set_meta("dimensions_m",size*uniform*parent_scale)
    model.set_meta("source_path",imported.get_meta("source_path", "procedural placeholder") if imported else "procedural placeholder")
    model.set_meta("provisional",imported == null)
    model.set_meta("weapon_id",id)
    return true

static func _marker(model: Node3D, name: String, position: Vector3) -> void:
    var existing := model.get_node_or_null(name)
    var marker := existing as Marker3D
    if marker == null:
        if existing != null:
            # The procedural fallback already has a mesh called Grip.
            # Keep that geometry, reserving the socket name for a Marker3D.
            existing.name = name + "Mesh"
        marker = Marker3D.new()
        marker.name = name
        model.add_child(marker)
    marker.position = position

static func stance(id: String, state: String) -> Dictionary:
    # right/up/forward offsets from the animated chest, expressed in metres.
    var pistol := id == "pistol"
    var offset := Vector3(0.16,-0.10,0.18)
    var pitch := -0.35
    match state:
        "walk":
            offset=Vector3(0.16,-0.07,0.20)
            pitch=-0.28
        "run":
            offset=Vector3(0.17,-0.08,0.22)
            pitch=-0.70
        "crouch":
            offset=Vector3(0.16,-0.04,0.20)
            pitch=-0.22
        "reload":
            offset=Vector3(0.14,0.005,0.20)
            pitch=-0.12
        "aim":
            var up: float = {"pistol":0.17,"rifle":0.005,"sniper":0.11,"shotgun":0.15,"smg":0.015}.get(id,0.04)
            offset=Vector3(0.15 if not pistol else 0.10,up,0.18 if pistol else 0.15)
            pitch=0.0
    if pistol and state != "aim":
        offset=Vector3(0.12,-0.035 if state!="run" else -0.10,0.20)
        pitch=-0.08 if state!="run" else -0.5
    return {"offset":offset,"pitch":pitch}
