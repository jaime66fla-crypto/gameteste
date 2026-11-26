extends Node3D
## CS-style first-person viewmodel: weapon in the lower-right corner with
## simple forearms, attached to the camera. Presentation only; shots still
## travel along the camera axis (crosshair centre).
const WeaponProportions = preload("res://scripts/weapons/WeaponProportions.gd")
const StoreCatalog = preload("res://scripts/loja/store_catalog.gd")
## Registro de personagens carregado na hora (preload aqui faria um ciclo:
## registro → personagens → ... → esta mira).
const REGISTRY_PATH := "res://scripts/characters/character_registry.gd"
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
## ADS (CoD-style): the weapon's "Sight" marker slides onto the screen centre,
## this far in front of the eye (metres), per weapon.
const ADS_EYE_DISTANCE := {
    "pistol": 0.30,
    "smg": 0.30,
    "rifle": 0.30,
    "shotgun": 0.30,
    "sniper": 0.28,
}
## The low-poly optics are solid blocks (no glass), so the eye line rests just
## above the weapon's highest point, like the tip of an iron-sight post.
const ADS_TOP_CLEARANCE := 0.003
## Weapons with an optic: a window is cut through the solid housing (weapon
## model space, before scaling) and the eye looks through its centre, where
## the HUD draws the red dot. Measured from the Polyy carbine geometry.
const OPTIC_WINDOW := {
    "rifle": AABB(Vector3(-0.029, 0.178, -0.08), Vector3(0.062, 0.074, 0.17)),
}
const OpticWindowShader = preload("res://scripts/weapons/optic_window.gdshader")
## Hip -> sights time (s); eased with smoothstep.
@export var ads_time := 0.24
## Mouse sway: radians of weapon lag per radian/s of look, and its limit.
@export var sway_amount := 0.012
@export var sway_limit := 0.06
@export var sway_smoothing := 10.0
## Fractions kept while fully aimed down sights.
@export var ads_bob_scale := 0.25
@export var ads_sway_scale := 0.3
@export var ads_kick_rotation_scale := 0.5

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
var _joint: StandardMaterial3D # null: joints take the surrounding surface
var _sleeve_style := "rolled"

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

## Dresses the arms like the chosen character (CharacterDefinition fp_* fields).
func apply_character(definition: Resource) -> void:
    if definition == null or not ("fp_sleeve" in definition):
        return
    var sleeve: Color = definition.fp_sleeve
    var skin: Color = definition.fp_skin
    var glove: Color = definition.fp_glove
    var gloves: bool = definition.fp_gloves
    var joint: Color = definition.fp_joint
    # Fabric materials are cached and shared: swap them, never recolour them.
    _sleeve = SurfaceMaterials.make("fabric", sleeve, false)
    _sleeve_roll = SurfaceMaterials.make("fabric", sleeve.darkened(0.15), false)
    _skin = _plain(skin, 0.68)
    _glove = _plain(glove, 0.72) if gloves else _skin
    _glove_detail = _plain(glove.lightened(0.08), 0.6) if gloves else _plain(skin.darkened(0.07), 0.7)
    _joint = _plain(joint, 0.5) if joint.a > 0.0 else null
    _sleeve_style = str(definition.fp_sleeve_style)
    # Takes effect on the next build() (the player calls it right after).

func build(id: String) -> void:
    weapon_id = id
    if weapon != null:
        holder.remove_child(weapon)
        weapon.queue_free()
    weapon = Node3D.new()
    weapon.name = "ViewWeapon"
    holder.add_child(weapon)
    # Skin de arma equipada no cofre (loja).
    var skin: String = load(REGISTRY_PATH).weapon_skin(id)
    var imported := WeaponProportions.create_model(id, StoreCatalog.texture_path(skin))
    if imported != null:
        weapon.add_child(imported)
    else:
        WeaponVisuals.build(weapon, id)
    WeaponProportions.apply(weapon, id, imported)
    for mesh in weapon.find_children("*", "GeometryInstance3D", true, false):
        (mesh as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    holder.position = HOLD.get(id, HOLD["rifle"])
    holder.rotation = BASE_ROTATION
    _cut_optic_window()
    _aim_point = _compute_aim_point()
    _build_arms()

## True when the current weapon is looked at through an optic (red dot).
func has_optic() -> bool:
    return OPTIC_WINDOW.has(weapon_id) and weapon != null and weapon.get_meta("optic_window", false)

## Replaces the viewmodel copy's material with one that keeps its look but cuts
## the optic window. The third-person weapon and the shared resource are untouched.
func _cut_optic_window() -> void:
    if not OPTIC_WINDOW.has(weapon_id) or not weapon.is_inside_tree():
        return
    var window: AABB = OPTIC_WINDOW[weapon_id]
    var to_weapon := weapon.global_transform.affine_inverse()
    var cut := false
    for node in weapon.find_children("*", "MeshInstance3D", true, false):
        var mesh_instance := node as MeshInstance3D
        if mesh_instance.mesh == null:
            continue
        var to_mesh := (to_weapon * mesh_instance.global_transform).affine_inverse()
        var box: AABB = to_mesh * window
        var source := mesh_instance.get_active_material(0) as BaseMaterial3D
        var material := ShaderMaterial.new()
        material.shader = OpticWindowShader
        if source != null:
            material.set_shader_parameter("albedo_color", source.albedo_color)
            material.set_shader_parameter("use_texture", source.albedo_texture != null)
            if source.albedo_texture != null:
                material.set_shader_parameter("albedo_texture", source.albedo_texture)
            material.set_shader_parameter("roughness", source.roughness)
            material.set_shader_parameter("metallic", source.metallic)
            if source.roughness_texture != null:
                material.set_shader_parameter("use_roughness_texture", true)
                material.set_shader_parameter("roughness_texture", source.roughness_texture)
                material.set_shader_parameter("roughness_channel", _channel_mask(source.roughness_texture_channel))
            if source.metallic_texture != null:
                material.set_shader_parameter("use_metallic_texture", true)
                material.set_shader_parameter("metallic_texture", source.metallic_texture)
                material.set_shader_parameter("metallic_channel", _channel_mask(source.metallic_texture_channel))
        material.set_shader_parameter("cut_min", box.position)
        material.set_shader_parameter("cut_max", box.end)
        mesh_instance.material_override = material
        cut = true
    weapon.set_meta("optic_window", cut)

static func _channel_mask(channel: int) -> Vector4:
    match channel:
        BaseMaterial3D.TEXTURE_CHANNEL_RED: return Vector4(1, 0, 0, 0)
        BaseMaterial3D.TEXTURE_CHANNEL_GREEN: return Vector4(0, 1, 0, 0)
        BaseMaterial3D.TEXTURE_CHANNEL_BLUE: return Vector4(0, 0, 1, 0)
        BaseMaterial3D.TEXTURE_CHANNEL_ALPHA: return Vector4(0, 0, 0, 1)
    return Vector4(0.333, 0.333, 0.333, 0) # grayscale

## Holder-space point that ADS puts on the screen centre: the Sight marker,
## raised to clear the top of the weapon geometry.
func _compute_aim_point() -> Vector3:
    var sight := weapon.get_node_or_null("Sight") as Marker3D
    if sight == null:
        return Vector3.INF
    var point := weapon.transform * sight.position
    if has_optic():
        # Look through the centre of the cut window.
        var window: AABB = OPTIC_WINDOW[weapon_id]
        var centre := weapon.transform * window.get_center()
        return Vector3(centre.x, centre.y, point.z)
    if not weapon.is_inside_tree():
        return point
    var top := -INF
    var to_weapon := weapon.global_transform.affine_inverse()
    for node in weapon.find_children("*", "VisualInstance3D", true, false):
        var visual := node as VisualInstance3D
        var box: AABB = (to_weapon * visual.global_transform) * visual.get_aabb()
        top = maxf(top, box.end.y)
    if top > -INF:
        # The weapon node only scales and offsets (no rotation): its Y is holder Y.
        point.y = maxf(point.y, (weapon.transform * Vector3(0.0, top, 0.0)).y + ADS_TOP_CLEARANCE)
    return point

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
    match _sleeve_style:
        "long":
            # Sleeve down to the wrist, with a slightly thicker cuff.
            var cuff := wrist - forearm_dir * 0.03
            _tube(arms, side + "UpperArm", shoulder, elbow, 0.056, _sleeve, 0.049)
            _ball(arms, side + "Elbow", elbow, 0.049, _joint if _joint else _sleeve)
            _tube(arms, side + "Sleeve", elbow, cuff, 0.049, _sleeve, 0.041)
            _tube(arms, side + "Cuff", cuff, wrist + forearm_dir * 0.004, 0.043, _sleeve_roll, 0.042)
        "short", "none":
            # T-shirt sleeve ending mid upper arm (or no sleeve), bare arm below.
            var hem := shoulder.lerp(elbow, 0.5)
            var skin_from := shoulder
            if _sleeve_style == "short":
                _tube(arms, side + "UpperArm", shoulder, hem, 0.058, _sleeve, 0.055)
                _tube(arms, side + "Hem", hem - (elbow - shoulder).normalized() * 0.012, hem + (elbow - shoulder).normalized() * 0.006, 0.059, _sleeve_roll, 0.058)
                skin_from = hem
            _tube(arms, side + "Bicep", skin_from, elbow, 0.046, _skin, 0.040)
            _ball(arms, side + "Elbow", elbow, 0.040, _joint if _joint else _skin)
            _tube(arms, side + "Forearm", elbow, wrist, 0.040, _skin, 0.031)
        _:
            var roll := elbow.lerp(wrist, 0.62)
            _tube(arms, side + "UpperArm", shoulder, elbow, 0.056, _sleeve, 0.049)
            _ball(arms, side + "Elbow", elbow, 0.049, _joint if _joint else _sleeve)
            _tube(arms, side + "Sleeve", elbow, roll, 0.049, _sleeve, 0.045)
            # Rolled-up sleeve band.
            _tube(arms, side + "Roll", roll - forearm_dir * 0.012, roll + forearm_dir * 0.03, 0.052, _sleeve_roll, 0.050)
            _tube(arms, side + "Forearm", roll, wrist, 0.038, _skin, 0.031)
    if _joint:
        _ball(arms, side + "WristJoint", wrist - forearm_dir * 0.006, 0.027, _joint)
    if _glove == _skin:
        # Bare hand: a slim wrist that blends forearm into the palm.
        _tube(arms, side + "Wrist", wrist - forearm_dir * 0.01, wrist + forearm_dir * 0.03, 0.031, _skin, 0.027)
    else:
        # Snug glove cuff, tapering into the hand (no wide flat ring).
        _tube(arms, side + "GloveCuff", wrist - forearm_dir * 0.008, wrist + forearm_dir * 0.03, 0.0335, _glove, 0.028)
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
    # Back of the hand: a flattened, tapered ellipsoid instead of a box.
    _ellipsoid(fist, "Palm", Vector3(0, 0, -0.004), Vector3(0.07, 0.044, 0.08), _glove)
    # Knuckle ridge where the fingers start.
    _capsule(fist, "Knuckles", Vector3(0, 0.006, -0.036), Vector3.RIGHT, 0.064, 0.014, _glove)
    # Four rounded fingers, two segments each, curled under the weapon.
    for i in range(4):
        var x := (-0.0255 + i * 0.017)
        var length := 0.026 if i in [1, 2] else 0.022
        var radius := 0.0085 if i in [1, 2] else 0.0078
        var knuckle := Node3D.new()
        knuckle.name = "Finger%d" % i
        fist.add_child(knuckle)
        knuckle.position = Vector3(x, 0.008, -0.040)
        knuckle.rotation.x = -0.9
        _capsule(knuckle, "Proximal", Vector3(0, 0, -length * 0.5), Vector3.FORWARD, length + radius * 2.0, radius, _glove_detail)
        var tip := Node3D.new()
        knuckle.add_child(tip)
        tip.position = Vector3(0, 0, -length)
        tip.rotation.x = -1.1
        _capsule(tip, "Distal", Vector3(0, 0, -0.01), Vector3.FORWARD, 0.022 + radius * 1.8, radius * 0.93, _glove)
    # Thumb wraps over the grip on the weapon side.
    var thumb := Node3D.new()
    thumb.name = "Thumb"
    fist.add_child(thumb)
    # Laid along the weapon's side, pointing forward, not sticking up.
    thumb.position = Vector3(-0.030 * outward, 0.002, -0.014)
    thumb.rotation = Vector3(-0.12, 0.32 * outward, 0.0)
    _ellipsoid(thumb, "ThumbPad", Vector3(0.006 * outward, -0.004, 0.008), Vector3(0.026, 0.028, 0.038), _glove)
    _capsule(thumb, "ThumbBase", Vector3(0, 0, -0.012), Vector3.FORWARD, 0.026 + 0.02, 0.010, _glove)
    var thumb_tip := Node3D.new()
    thumb.add_child(thumb_tip)
    thumb_tip.position = Vector3(0, 0, -0.026)
    thumb_tip.rotation.y = -0.18 * outward
    _capsule(thumb_tip, "ThumbTip", Vector3(0, 0, -0.01), Vector3.FORWARD, 0.018 + 0.017, 0.0088, _glove_detail)

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

## Rounded segment centred on pos, lying along axis; length includes the caps.
func _capsule(parent: Node3D, node_name: String, pos: Vector3, axis: Vector3, length: float, radius: float, material: Material) -> void:
    var mesh := MeshInstance3D.new()
    mesh.name = node_name
    var capsule := CapsuleMesh.new()
    capsule.radius = radius
    capsule.height = maxf(length, radius * 2.0)
    capsule.radial_segments = 12
    capsule.rings = 4
    mesh.mesh = capsule
    mesh.position = pos
    # CapsuleMesh runs along +Y.
    mesh.quaternion = Quaternion(Vector3.UP, axis.normalized())
    mesh.material_override = material
    mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    parent.add_child(mesh)

## Sphere stretched to the given full size (width, height, depth).
func _ellipsoid(parent: Node3D, node_name: String, pos: Vector3, size: Vector3, material: Material) -> void:
    var mesh := MeshInstance3D.new()
    mesh.name = node_name
    var sphere := SphereMesh.new()
    sphere.radius = 0.5
    sphere.height = 1.0
    sphere.radial_segments = 16
    sphere.rings = 8
    mesh.mesh = sphere
    mesh.position = pos
    mesh.scale = size
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
var _ads_weight := 0.0
var _sway := Vector2.ZERO
var _last_physics_frame := -10
var _aim_point := Vector3.INF

## Holder position that puts the aim point on the camera axis.
func _ads_position() -> Vector3:
    if weapon == null or _aim_point == Vector3.INF:
        return HOLD.get(weapon_id, HOLD["rifle"])
    var distance: float = ADS_EYE_DISTANCE.get(weapon_id, 0.30)
    return Vector3(0.0, 0.0, -distance) - _aim_point

## Rest pose blended between hip and sights (no recoil, wall or reload offsets).
func _rest_position() -> Vector3:
    var hip: Vector3 = HOLD.get(weapon_id, HOLD["rifle"])
    return hip.lerp(_ads_position(), smoothstep(0.0, 1.0, _ads_weight))

func _rest_rotation() -> Vector3:
    return BASE_ROTATION.lerp(Vector3.ZERO, smoothstep(0.0, 1.0, _ads_weight))

## 0 = hip, 1 = fully aimed down sights.
func ads_amount() -> float:
    return smoothstep(0.0, 1.0, _ads_weight)

## Weapon length from grip to muzzle (metres), used to detect walls ahead.
func reach() -> float:
    var muzzle := weapon.get_node_or_null("Muzzle") as Marker3D if weapon != null else null
    if muzzle == null:
        return 0.6
    # Rest pose only, so the wall tilt does not feed back into the measurement.
    return -(_rest_position() + Basis.from_euler(_rest_rotation()) * (weapon.transform * muzzle.position)).z

## kick: recoil; bob: walk sway (m); flash_on: muzzle flash; reloading: lower and
## tilt the weapon; wall_clearance: free distance ahead of the camera (m);
## look_delta: mouse look this frame (yaw, pitch radians) for weapon sway.
func animate(delta: float, kick: float, bob: float, flash_on: bool, reloading: bool = false, wall_clearance: float = INF, look_delta: Vector2 = Vector2.ZERO) -> void:
    # Each entry into first person starts from the hip and raises the sights.
    var frame := Engine.get_physics_frames()
    if frame - _last_physics_frame > 2:
        _ads_weight = 0.0
        _sway = Vector2.ZERO
    _last_physics_frame = frame
    _reload_weight = move_toward(_reload_weight, 1.0 if reloading else 0.0, delta * 5.0)
    # 0 = free, 1 = muzzle would be inside the wall: pull back and raise the barrel.
    var blocked := clampf((reach() + 0.05 - wall_clearance) / maxf(reach(), 0.1), 0.0, 1.0)
    _wall_weight = lerpf(_wall_weight, blocked, minf(1.0, delta * 14.0))
    # Reloading or a wall in front drops out of the sights, like CoD.
    var wants_ads := not reloading and _wall_weight < 0.35
    _ads_weight = move_toward(_ads_weight, 1.0 if wants_ads else 0.0, delta / maxf(ads_time, 0.01))
    var ads := ads_amount()
    var reload_ease := smoothstep(0.0, 1.0, _reload_weight)
    # Sway: the weapon lags behind the look direction, clamped and smoothed.
    var sway_target := Vector2.ZERO
    if delta > 0.0:
        sway_target = (-look_delta / delta * sway_amount).limit_length(sway_limit) * lerpf(1.0, ads_sway_scale, ads)
    _sway = _sway.lerp(sway_target, minf(1.0, delta * sway_smoothing))
    var recoil := Vector3(0.0, bob * lerpf(1.0, ads_bob_scale, ads) + kick * 0.04, kick * 0.12)
    var reload_offset := Vector3(-0.04, -0.12, 0.04) * reload_ease
    # Low ready against walls: drop the weapon so the barrel leaves the view.
    var wall_offset := Vector3(0.05, -0.24, 0.06) * _wall_weight
    var sway_offset := Vector3(-_sway.x, _sway.y, 0.0) * 0.25
    position = recoil + reload_offset + wall_offset + sway_offset
    rotation = Vector3(kick * 0.18 * lerpf(1.0, ads_kick_rotation_scale, ads), 0.0, 0.0)
    holder.position = _rest_position()
    # Tilt about the grip: barrel down against walls, rolled and dipped while reloading.
    holder.rotation = _rest_rotation() + Vector3(-0.5 * _wall_weight - 0.3 * reload_ease + _sway.y, 0.25 * _wall_weight + _sway.x, 0.6 * reload_ease - _sway.x * 0.5)
    flash_on = flash_on and _wall_weight < 0.5
    var muzzle := weapon.get_node_or_null("Muzzle") as Marker3D if weapon != null else null
    flash.visible = flash_on and muzzle != null
    if muzzle != null:
        flash.global_position = muzzle.global_position

func muzzle_position() -> Vector3:
    var muzzle := weapon.get_node_or_null("Muzzle") as Marker3D if weapon != null else null
    return muzzle.global_position if muzzle != null else global_position
