extends Node3D
## CS-style first-person viewmodel: weapon in the lower-right corner with
## simple forearms, attached to the camera. Presentation only; shots still
## travel along the camera axis (crosshair centre).
const WeaponProportions = preload("res://scripts/weapons/WeaponProportions.gd")
const WeaponVisuals = preload("res://scripts/weapon_visuals.gd")
const SurfaceMaterials = preload("res://scripts/surface_materials.gd")

# Grip position in camera space (right, up, forward) per weapon.
const HOLD := {
    "pistol": Vector3(0.11, -0.15, -0.46),
    "smg": Vector3(0.19, -0.22, -0.48),
    "rifle": Vector3(0.19, -0.22, -0.52),
    "shotgun": Vector3(0.17, -0.19, -0.32),
    "sniper": Vector3(0.19, -0.22, -0.52),
}
const RIGHT_SHOULDER := Vector3(0.24, -0.32, 0.10)
const LEFT_SHOULDER := Vector3(-0.22, -0.34, 0.08)
# Toe the barrel slightly inward so it points toward the crosshair.
const BASE_ROTATION := Vector3(0.0, 0.05, 0.0)

var holder: Node3D
var weapon: Node3D
var arms: Node3D
var flash: MeshInstance3D
var weapon_id := ""
var _sleeve: StandardMaterial3D
var _sleeve_roll: StandardMaterial3D
var _skin: StandardMaterial3D
var _glove: StandardMaterial3D
var _glove_detail: StandardMaterial3D

static func _plain(color: Color, roughness: float) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    return material

func _ready() -> void:
    # Tactical olive fabric with the shared procedural weave texture.
    _sleeve = SurfaceMaterials.make("fabric", Color("#56603f"), false)
    _sleeve_roll = SurfaceMaterials.make("fabric", Color("#48512f"), false)
    _skin = _plain(Color("#8a624d"), 0.68)
    _glove = _plain(Color("#1c1e21"), 0.72)
    _glove_detail = _plain(Color("#2c3034"), 0.6)
    holder = Node3D.new()
    holder.name = "Holder"
    add_child(holder)
    # Arms live under the holder so they follow the weapon when it tilts at the grip.
    arms = Node3D.new()
    arms.name = "Arms"
    holder.add_child(arms)
    flash = MeshInstance3D.new()
    flash.name = "ViewFlash"
    var sphere := SphereMesh.new()
    sphere.radius = 0.045
    sphere.height = 0.09
    flash.mesh = sphere
    var glow := StandardMaterial3D.new()
    glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    glow.albedo_color = Color("#ffc267")
    flash.material_override = glow
    flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    flash.visible = false
    add_child(flash)

func build(id: String) -> void:
    weapon_id = id
    if weapon != null:
        holder.remove_child(weapon)
        weapon.queue_free()
    weapon = Node3D.new()
    weapon.name = "ViewWeapon"
    holder.add_child(weapon)
    var imported := WeaponProportions.create_model(id)
    if imported != null:
        weapon.add_child(imported)
    else:
        WeaponVisuals.build(weapon, id)
    WeaponProportions.apply(weapon, id, imported)
    for mesh in weapon.find_children("*", "GeometryInstance3D", true, false):
        (mesh as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    holder.position = HOLD.get(id, HOLD["rifle"])
    holder.rotation = BASE_ROTATION
    _build_arms()

func _build_arms() -> void:
    for child in arms.get_children():
        arms.remove_child(child)
        child.queue_free()
    for side in ["Right", "Left"]:
        var marker := weapon.get_node_or_null(side + "Grip") as Marker3D
        if marker == null:
            continue
        # Holder space: computed from the camera-space rest pose.
        var hand := holder.to_local(marker.global_position)
        var shoulder := holder.to_local(to_global(RIGHT_SHOULDER if side == "Right" else LEFT_SHOULDER))
        _build_arm(side, shoulder, hand)

## Two-bone arm: upper sleeve, elbow, rolled cuff, bare forearm, gloved fist.
func _build_arm(side: String, shoulder: Vector3, hand: Vector3) -> void:
    var outward := 1.0 if side == "Right" else -1.0
    var reach_len := shoulder.distance_to(hand)
    # Segments always slightly longer than half the reach, so the elbow bends.
    var upper_len := maxf(0.28, reach_len * 0.56)
    var fore_len := upper_len * 0.95
    # Elbow drops down and out, like a shooter's stance.
    var pole := holder.basis.inverse() * Vector3(0.55 * outward, -1.0, 0.15)
    var elbow := _solve_elbow(shoulder, hand, upper_len, fore_len, pole)
    var forearm_dir := (hand - elbow).normalized()
    var wrist := hand - forearm_dir * 0.055
    var roll := elbow.lerp(wrist, 0.62)
    _tube(arms, side + "UpperArm", shoulder, elbow, 0.056, _sleeve, 0.049)
    _ball(arms, side + "Elbow", elbow, 0.049, _sleeve)
    _tube(arms, side + "Sleeve", elbow, roll, 0.049, _sleeve, 0.045)
    # Rolled-up sleeve band.
    _tube(arms, side + "Roll", roll - forearm_dir * 0.012, roll + forearm_dir * 0.03, 0.052, _sleeve_roll, 0.050)
    _tube(arms, side + "Forearm", roll, wrist, 0.038, _skin, 0.031)
    _tube(arms, side + "GloveCuff", wrist - forearm_dir * 0.012, wrist + forearm_dir * 0.022, 0.036, _glove, 0.035)
    _build_fist(side, hand, forearm_dir, outward)

func _solve_elbow(shoulder: Vector3, hand: Vector3, upper_len: float, fore_len: float, pole: Vector3) -> Vector3:
    var to_hand := hand - shoulder
    var distance := clampf(to_hand.length(), 0.01, upper_len + fore_len - 0.001)
    var direction := to_hand.normalized()
    var along := (upper_len * upper_len - fore_len * fore_len + distance * distance) / (2.0 * distance)
    var height := sqrt(maxf(upper_len * upper_len - along * along, 0.0))
    var bend := (pole - direction * pole.dot(direction)).normalized()
    return shoulder + direction * along + bend * height

func _build_fist(side: String, center: Vector3, forearm_dir: Vector3, outward: float) -> void:
    var fist := Node3D.new()
    fist.name = side + "Hand"
    arms.add_child(fist)
    fist.position = center
    # -Z follows the forearm; +Y stays near the weapon's top.
    var up_hint := Vector3.UP if absf(forearm_dir.dot(Vector3.UP)) < 0.95 else Vector3.BACK
    fist.basis = Basis.looking_at(forearm_dir, up_hint)
    # Back of the hand / palm block.
    _block(fist, "Palm", Vector3(0, 0, 0), Vector3(0.072, 0.05, 0.075), _glove)
    # Four fingers, two segments each, curled under the weapon.
    for i in range(4):
        var x := (-0.027 + i * 0.018)
        var length := 0.024 if i in [1, 2] else 0.021
        var knuckle := Node3D.new()
        knuckle.name = "Finger%d" % i
        fist.add_child(knuckle)
        knuckle.position = Vector3(x, 0.012, -0.040)
        knuckle.rotation.x = -0.9
        _block(knuckle, "Proximal", Vector3(0, 0, -length * 0.5), Vector3(0.016, 0.019, length), _glove_detail)
        var tip := Node3D.new()
        knuckle.add_child(tip)
        tip.position = Vector3(0, 0, -length)
        tip.rotation.x = -1.1
        _block(tip, "Distal", Vector3(0, 0, -0.01), Vector3(0.015, 0.017, 0.022), _glove)
    # Thumb wraps over the grip on the weapon side.
    var thumb := Node3D.new()
    thumb.name = "Thumb"
    fist.add_child(thumb)
    thumb.position = Vector3(-0.036 * outward, 0.008, -0.012)
    thumb.rotation = Vector3(0.25, 0.65 * outward, 0.0)
    _block(thumb, "ThumbBase", Vector3(0, 0, -0.016), Vector3(0.02, 0.022, 0.034), _glove)
    _block(thumb, "ThumbTip", Vector3(0, 0, -0.042), Vector3(0.018, 0.019, 0.024), _glove_detail)

func _block(parent: Node3D, node_name: String, pos: Vector3, size: Vector3, material: Material) -> void:
    var mesh := MeshInstance3D.new()
    mesh.name = node_name
    var box := BoxMesh.new()
    box.size = size
    mesh.mesh = box
    mesh.position = pos
    mesh.material_override = material
    mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    parent.add_child(mesh)

func _ball(parent: Node3D, node_name: String, pos: Vector3, radius: float, material: Material) -> void:
    var mesh := MeshInstance3D.new()
    mesh.name = node_name
    var sphere := SphereMesh.new()
    sphere.radius = radius
    sphere.height = radius * 2.0
    sphere.radial_segments = 12
    sphere.rings = 6
    mesh.mesh = sphere
    mesh.position = pos
    mesh.material_override = material
    mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    parent.add_child(mesh)

func _tube(parent: Node3D, node_name: String, a: Vector3, b: Vector3, radius: float, material: Material, end_radius: float = -1.0) -> void:
    var axis := b - a
    if axis.length() < 0.001:
        return
    var mesh := MeshInstance3D.new()
    mesh.name = node_name
    var cylinder := CylinderMesh.new()
    # CylinderMesh top (+Y) is mapped onto b.
    cylinder.top_radius = end_radius if end_radius > 0.0 else radius * 0.85
    cylinder.bottom_radius = radius
    cylinder.height = axis.length()
    cylinder.radial_segments = 10
    mesh.mesh = cylinder
    mesh.position = (a + b) * 0.5
    mesh.quaternion = Quaternion(Vector3.UP, axis.normalized())
    mesh.material_override = material
    mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    parent.add_child(mesh)

var _reload_weight := 0.0
var _wall_weight := 0.0

## Weapon length from grip to muzzle (metres), used to detect walls ahead.
func reach() -> float:
    var muzzle := weapon.get_node_or_null("Muzzle") as Marker3D if weapon != null else null
    if muzzle == null:
        return 0.6
    # Rest pose only, so the wall tilt does not feed back into the measurement.
    return -(holder.position + Basis.from_euler(BASE_ROTATION) * (weapon.transform * muzzle.position)).z

## kick: recoil; bob: walk sway (m); flash_on: muzzle flash; reloading: lower and
## tilt the weapon; wall_clearance: free distance ahead of the camera (m).
func animate(delta: float, kick: float, bob: float, flash_on: bool, reloading: bool = false, wall_clearance: float = INF) -> void:
    _reload_weight = move_toward(_reload_weight, 1.0 if reloading else 0.0, delta * 5.0)
    # 0 = free, 1 = muzzle would be inside the wall: pull back and raise the barrel.
    var blocked := clampf((reach() + 0.05 - wall_clearance) / maxf(reach(), 0.1), 0.0, 1.0)
    _wall_weight = lerpf(_wall_weight, blocked, minf(1.0, delta * 14.0))
    var reload_ease := smoothstep(0.0, 1.0, _reload_weight)
    var recoil := Vector3(0.0, bob + kick * 0.04, kick * 0.12)
    var reload_offset := Vector3(-0.04, -0.12, 0.04) * reload_ease
    # Low ready against walls: drop the weapon so the barrel leaves the view.
    var wall_offset := Vector3(0.05, -0.24, 0.06) * _wall_weight
    position = recoil + reload_offset + wall_offset
    rotation = Vector3(kick * 0.18, 0.0, 0.0)
    # Tilt about the grip: barrel down against walls, rolled and dipped while reloading.
    holder.rotation = BASE_ROTATION + Vector3(-0.5 * _wall_weight - 0.3 * reload_ease, 0.25 * _wall_weight, 0.6 * reload_ease)
    flash_on = flash_on and _wall_weight < 0.5
    var muzzle := weapon.get_node_or_null("Muzzle") as Marker3D if weapon != null else null
    flash.visible = flash_on and muzzle != null
    if muzzle != null:
        flash.global_position = muzzle.global_position

func muzzle_position() -> Vector3:
    var muzzle := weapon.get_node_or_null("Muzzle") as Marker3D if weapon != null else null
    return muzzle.global_position if muzzle != null else global_position
