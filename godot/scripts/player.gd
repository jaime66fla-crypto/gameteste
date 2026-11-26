extends CharacterBody3D
const PointerMode = preload("res://scripts/pointer_mode.gd")
## Emitted once per trigger pull with the visible tracer path (online matches relay it).
signal shot_fired(weapon_id: String, from: Vector3, to: Vector3)

# Ghost-style configurable character dimensions and movement (Godot 4).
@export_category("Atributos do Soldado")
@export_range(1.5, 2.1, 0.01) var height: float = 1.80
@export_range(2.0, 10.0, 0.1) var speed: float = 5.0
@export_range(1.0, 2.5, 0.05) var sprint_multiplier: float = 1.6
@export_range(2.0, 12.0, 0.1) var jump_velocity: float = 8.5
@export_range(0.0005, 0.01, 0.0001) var mouse_sensitivity: float = 0.0025
@export_range(0.24, 0.48, 0.01) var collision_radius: float = 0.34
const SurfaceMaterials = preload("res://scripts/surface_materials.gd")
const CROUCH_SPEED := 2.7
## Holding Alt walks (GTA-style); matches the natural unarmed walk cycle so the
## feet do not slide.
const WALK_SPEED := 1.6
const PRONE_SPEED := 0.9 # rastejando
@export_range(1.0, 60.0, 0.5) var acceleration := 24.0
@export_range(1.0, 60.0, 0.5) var deceleration := 30.0
var body_collision: CollisionShape3D
var body_capsule: CapsuleShape3D
var standing_probe: CapsuleShape3D
var sprinting := false
const WeaponData = preload("res://scripts/weapon_data.gd")
const MAG_SIZE := 15
const SoundFXScript = preload("res://scripts/sound_fx.gd")
const Controls = preload("res://scripts/controls.gd")
const HumanoidAvatarScript = preload("res://scripts/avatar/avatar_controller.gd")
const CharacterRegistry = preload("res://scripts/characters/character_registry.gd")
const WeaponProportions = preload("res://scripts/weapons/WeaponProportions.gd")
const FirstPersonViewmodel = preload("res://scripts/weapons/first_person_viewmodel.gd")
const HitboxScript = preload("res://scripts/net/hitbox.gd")
## Holding aim (except the sniper scope) switches to a CS-style first-person view.
const BASE_FOV := 72.0
## ADS zoom per weapon (CoD-like: iron sights ~1.1x, red dot/holo ~1.2-1.3x),
## applied to the base FOV. The sniper uses its own scope.
const ADS_ZOOM := {"pistol": 1.10, "shotgun": 1.10, "smg": 1.20, "rifle": 1.30}
## ADS look speed follows the zoom (1 = same angle per mouse count as the zoom ratio).
@export_range(0.0, 1.5, 0.05) var ads_sensitivity_scale: float = 1.0
var _look_delta := Vector2.ZERO
const FIRST_PERSON_CUTOFF := 0.45 # spring length below which the body is hidden
const BARREL_CLEARANCE := 0.75 # cover lip right past the barrel does not eat the shot (the head sees over it)
const AIM_BLOCK_MARGIN := 0.6 # the round stops this much short of the crosshair point = show "blocked"
var viewmodel: Node3D
var first_person_view := false
var hit_shake := 0.0 # camera jolt when this player takes damage
## Online matches: weapons must be found in loot crates. Offline practice keeps all five.
var loadout_limited := false
var owned_weapons: Dictionary = {}
## Online loot: keys 1-5 follow pickup order (first weapon found is 1, the next 2...).
## Na Sobrevivência as armas brancas entram na mesma fila (melee_slots).
var slot_order: Array[String] = []
## Armas brancas que ocupam um slot: id do item -> nome mostrado.
var melee_slots: Dictionary = {}
## Set by the online match: returns true when E was used to open a crate.
var interact_handler: Callable
var heal_handler: Callable # F: use a carried medkit (online matches)
var melee_handler: Callable # Q: survival melee hit (zombies / players in front)
## Arma branca na mão (ex.: "long_bat" na arena do treino): a arma de fogo fica
## guardada e o clique esquerdo golpeia (melee_handler). Trocar de arma (1-5) larga.
var melee_weapon := ""
var bow_controller: Node

func has_bow() -> bool:
    return is_instance_valid(bow_controller) and bool(bow_controller.get("equipped"))

## Só arma de fogo na mão tem mira (botão direito e a mira na tela). Faca,
## bastão e mãos vazias acertam pelo alcance a partir do corpo (scripts/melee.gd).
func has_sights() -> bool:
    return has_bow() or (not weapon_holstered and melee_weapon.is_empty())
## Modo de construção ligado: o clique esquerdo coloca peças, não soca.
var attack_blocked := false

## Soco (clique esquerdo de mãos vazias, ou a tecla de soco): vira para a mira,
## toca o clipe e o melee_handler do modo aplica o dano (Combate, Sobrevivência, treino).
func _punch() -> void:
    if humanoid_avatar != null and humanoid_avatar.has_method("play_action"):
        face_aim(0.6) # o soco sai para a mira, mesmo correndo para outro lado
        humanoid_avatar.call("play_action", "punch")
    if melee_handler.is_valid():
        melee_handler.call()
var fishing_active := false
var ui_blocking: Callable # true enquanto uma janela (mochila, confirmação) precisa do cursor
## G: grenade. Online the match controller decides (inventory); offline it is
## unlimited with a short cooldown.
var grenade_handler: Callable
## Online: returns false (and warns) when there is no grenade to throw.
var grenade_check: Callable
var _grenade_cooldown := 0.0
## Hold G to aim (arc + blast circle preview), release to throw, Esc cancels.
var grenade_aiming := false
var _grenade_preview: Node3D
var _grenade_dots: MultiMeshInstance3D
var _grenade_ring: MeshInstance3D
var _grenade_impact: MeshInstance3D
const GRENADE_PREVIEW_DOTS := 64
const GrenadeScript = preload("res://scripts/weapons/grenade.gd")
## Lean (peek) while aiming: hold Q (left) / E (right) with the right mouse button.
const LEAN_DISTANCE := 0.42
const LEAN_ROLL := 0.2
var lean := 0.0 # -1 left .. 1 right
## Reload and medkit both take 3 s, shown as a clock under the crosshair.
const ACTION_TIME := 3.0
var water_query: Callable
var swimming := false
var channel_label := ""
var channel_total := 0.0
var channel_left := 0.0
var _channel_done: Callable
var last_shot_origin := Vector3.ZERO
@export var character_id: String = ""
var requested_character_id := ""
var character_fallback_reason := ""

var yaw := 0.0
var pitch := -0.14
var aiming := false
var scope_zoom := 4.0
var scope_was_active := false
var crouching := false
var prone := false # deitado (Ctrl duas vezes)
var stance := 0 # 0 em pé, 1 agachado, 2 deitado
var stance_changed := false
var ammo := MAG_SIZE
var reloading := false
var shots := 0
var fire_delay := 0.0
var reload_timer := 0.0
var camera: Camera3D
var arm_pivot: Node3D
var avatar: Node3D
var gun: Node3D
var gun_flash: OmniLight3D
var cam_distance := 3.6
var sound_fx: Node
var muzzle_flare: MeshInstance3D
var gun_kick := 0.0
var current_weapon := "pistol"
var weapon_holstered := false
## Escudo no braço esquerdo (item da sobrevivência): id do item ("" = sem escudo)
## e a guarda alta, que liga/desliga no botão FIXA (ação "shield").
var shield_id := ""
var shield_raised := false
const SHIELD_GUARD_SPEED := 2.5 # em guarda: anda, não corre
const SHIELD_ONE_HAND_SPREAD := 1.35 # arma longa numa mão só (a esquerda está no escudo)
var reserve_ammo := {"pistol": 90, "smg": 150, "rifle": 150, "shotgun": 36, "sniper": 25, "bow": 20}
var magazines := {"pistol": 15, "smg": 30, "rifle": 30, "shotgun": 6, "sniper": 5, "bow": 0}
var weapon_model: Node3D
var locomotion_clock := 0.0
var presentation_offset := Vector3.ZERO
var avatar_anim_time := 0.0
var equipped_external_model := false
var jaime_model: Node3D
var jaime_animation: AnimationPlayer
var jaime_animation_name := ""
var gun_uses_model_mount := false
var humanoid_avatar: Node3D

func _ready() -> void:
    # Keys chosen in Settings > Controls (also when the player runs without main.gd, e.g. in tests).
    if not InputMap.has_action("fire"):
        Controls.load_and_apply()
    # Characters share a layer: they block each other but bullets ignore the
    # capsules and hit body-part hitboxes instead.
    collision_layer = HitboxScript.LAYER_CHARACTERS
    collision_mask = HitboxScript.LAYER_WORLD | HitboxScript.LAYER_CHARACTERS
    var collision := CollisionShape3D.new()
    var capsule := CapsuleShape3D.new()
    capsule.radius = minf(collision_radius, height * 0.3)
    capsule.height = height
    collision.shape = capsule
    collision.position.y = height * 0.5
    add_child(collision)
    body_collision = collision
    body_capsule = capsule
    standing_probe = CapsuleShape3D.new()
    standing_probe.radius = capsule.radius
    standing_probe.height = height
    avatar = Node3D.new()
    add_child(avatar)
    _make_avatar()
    _install_selected_character()
    if humanoid_avatar != null and humanoid_avatar.has_method("bind_weapon"):
        _rebuild_weapon_model()
    sound_fx = SoundFXScript.new()
    sound_fx.name = "SoundFX"
    sound_fx.spatial_audio = false # Own shots/steps stay consistent as the camera moves.
    gun.add_child(sound_fx)
    arm_pivot = Node3D.new()
    arm_pivot.position = Vector3(0, height * 0.86, 0)
    add_child(arm_pivot)
    var spring := SpringArm3D.new()
    spring.spring_length = cam_distance
    spring.margin = 0.15
    # Uma esfera (e não um raio) segura a câmera longe da parede: o plano de
    # recorte da lente não atravessa a parede em ângulos rasos.
    var spring_probe := SphereShape3D.new()
    spring_probe.radius = 0.22
    spring.shape = spring_probe
    spring.collision_mask = HitboxScript.LAYER_WORLD
    spring.position.x = 1.0
    arm_pivot.add_child(spring)
    camera = Camera3D.new()
    camera.current = true
    camera.fov = 72
    spring.add_child(camera)
    spring.add_excluded_object(get_rid())
    viewmodel = FirstPersonViewmodel.new()
    viewmodel.name = "FirstPersonViewmodel"
    viewmodel.visible = false
    camera.add_child(viewmodel)
    _rebuild_viewmodel()
    bow_controller = preload("res://scripts/weapons/bow_controller.gd").new()
    add_child(bow_controller)
    bow_controller.setup(self)
    PointerMode.capture()

func _install_selected_character() -> void:
    requested_character_id = character_id if not character_id.is_empty() else CharacterRegistry.load_selection()
    character_id = requested_character_id
    var chosen := CharacterRegistry.create_visual(character_id)
    if chosen != null and chosen.has_method("vestir"):
        chosen.call("vestir", CharacterRegistry.load_outfit()) # cofre de roupas (menu)
    if chosen != null:
        chosen.scale *= height / 1.8
        avatar.add_child(chosen)
        var mount := chosen.get("weapon_mount") as Node3D
        var valid := not chosen.has_method("is_visual_ready") or bool(chosen.call("is_visual_ready"))
        if mount != null and valid:
            humanoid_avatar = chosen
            for part_name in ["Torso", "Head", "LeftLeg", "RightLeg", "LeftArm", "RightArm"]:
                var part := avatar.get_node_or_null(part_name) as Node3D
                if part:
                    part.visible = false
            gun.reparent(mount, false)
            gun.position = Vector3.ZERO
            gun.rotation = Vector3.ZERO
            gun_uses_model_mount = true
            humanoid_avatar.configure_weapon(current_weapon, weapon_model.scale.x)
            return
        avatar.remove_child(chosen)
        chosen.queue_free()
    character_fallback_reason = "Visual indisponível; usando Jaime Original. Escolha outro em Personagens."
    character_id = CharacterRegistry.DEFAULT_ID
    _install_humanoid_avatar()

func _install_humanoid_avatar() -> void:
    humanoid_avatar = HumanoidAvatarScript.new()
    humanoid_avatar.name = "HumanoidAvatar"
    # Match the visible character to the configured collision height.
    humanoid_avatar.scale = Vector3.ONE * (height / 2.09)
    avatar.add_child(humanoid_avatar)
    for old_part in ["Torso", "Head", "LeftLeg", "RightLeg", "LeftArm", "RightArm"]:
        var node := avatar.get_node_or_null(old_part) as Node3D
        if node != null:
            node.visible = false
    var mount := humanoid_avatar.get_node_or_null("WeaponMount") as Node3D
    if mount != null:
        gun.reparent(mount, false)
        gun.position = Vector3.ZERO
        gun.rotation = Vector3.ZERO
        gun_uses_model_mount = true
    humanoid_avatar.configure_weapon(current_weapon, weapon_model.scale.x)

func _material(c: Color) -> StandardMaterial3D:
    var kind := "wood" if c.to_html(false) == "765b43" else "metal"
    return SurfaceMaterials.make(kind, c, false)

func _part(parent: Node3D, name: String, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
    var part := MeshInstance3D.new()
    part.name = name
    var mesh := BoxMesh.new()
    mesh.size = size
    part.mesh = mesh
    part.position = pos
    part.material_override = _material(color)
    parent.add_child(part)
    return part

func _make_avatar() -> void:
    var uniform := Color(0.17,0.21,0.24)
    _part(avatar,"Torso",Vector3(0,1.25,0),Vector3(0.7,0.77,0.35),uniform)
    _part(avatar,"Head",Vector3(0,1.84,0),Vector3(0.35,0.36,0.34),Color(0.58,0.42,0.31))
    _part(avatar,"LeftLeg",Vector3(-0.18,0.48,0),Vector3(0.25,0.85,0.27),uniform)
    _part(avatar,"RightLeg",Vector3(0.18,0.48,0),Vector3(0.25,0.85,0.27),uniform)
    _part(avatar,"LeftArm",Vector3(-0.48,1.20,-0.17),Vector3(0.20,0.65,0.23),uniform)
    _part(avatar,"RightArm",Vector3(0.48,1.20,-0.17),Vector3(0.20,0.65,0.23),uniform)
    gun = Node3D.new()
    avatar.add_child(gun)
    gun.position = Vector3(0.33,1.28,-0.48)
    weapon_model = Node3D.new()
    gun.add_child(weapon_model)
    _part(weapon_model,"PistolBody",Vector3(0,0,-0.22),Vector3(0.16,0.20,0.52),Color(0.08,0.09,0.10))
    _part(weapon_model,"Grip",Vector3(0,-0.16,-0.08),Vector3(0.13,0.30,0.13),Color(0.11,0.11,0.12))
    _part(weapon_model,"Slide",Vector3(0,0.105,-0.27),Vector3(0.18,0.10,0.46),Color("#34393e"))
    _part(weapon_model,"SightRear",Vector3(0,0.18,-0.07),Vector3(0.11,0.05,0.06),Color("#141719"))
    _part(weapon_model,"SightFront",Vector3(0,0.18,-0.48),Vector3(0.08,0.05,0.05),Color("#141719"))
    _part(weapon_model,"Barrel",Vector3(0,0,-0.53),Vector3(0.10,0.10,0.20),Color("#262a30"))
    muzzle_flare = MeshInstance3D.new()
    var flash_mesh := SphereMesh.new()
    flash_mesh.radius = 0.15
    flash_mesh.height = 0.32
    muzzle_flare.mesh = flash_mesh
    var glow := StandardMaterial3D.new()
    glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    glow.albedo_color = Color("#ffc267")
    muzzle_flare.material_override = glow
    muzzle_flare.position = Vector3(0,0,-0.69)
    muzzle_flare.visible = false
    gun.add_child(muzzle_flare)
    gun_flash = OmniLight3D.new()
    gun_flash.position = Vector3(0,0,-0.57)
    gun_flash.light_color = Color(1,0.65,0.25)
    gun_flash.light_energy = 0
    gun_flash.visible = false
    gun.add_child(gun_flash)
    _rebuild_weapon_model()

func _find_descendant(node: Node, name_query: String) -> Node:
    if node.name == name_query:
        return node
    for child in node.get_children():
        var match_node := _find_descendant(child, name_query)
        if match_node != null:
            return match_node
    return null

func _first_animation_player(node: Node) -> AnimationPlayer:
    if node is AnimationPlayer:
        return node as AnimationPlayer
    for child in node.get_children():
        var found := _first_animation_player(child)
        if found != null:
            return found
    return null

func _load_jaime_avatar() -> void:
    # Use either the saved inherited scene or the original imported GLB.
    var model_path := "res://assets/jaime/jaime.glb"
    if not ResourceLoader.exists(model_path):
        return
    var path := "res://scenes/jaime personagem.tscn"
    if not ResourceLoader.exists(path):
        path = model_path
    var packed := load(path) as PackedScene
    if packed == null:
        packed = load(model_path) as PackedScene
    if packed == null:
        return
    var instance := packed.instantiate() as Node3D
    if instance == null:
        return
    jaime_model = instance
    jaime_model.name = "JaimeOriginal"
    avatar.add_child(jaime_model)
    # Rotate the mesh only, never the player controller or camera.
    jaime_model.rotation.y = PI
    jaime_animation = _first_animation_player(jaime_model)
    CharacterRegistry.configure_locomotion_loops(jaime_model)
    var embedded_weapon := _find_descendant(jaime_model, "Weapon_pistol") as Node3D
    if embedded_weapon != null:
        embedded_weapon.visible = false
    var weapon_mount := _find_descendant(jaime_model, "OperatorWeaponMount") as Node3D
    if weapon_mount != null:
        gun.reparent(weapon_mount, false)
        gun.position = Vector3.ZERO
        gun.rotation = Vector3.ZERO
        gun_uses_model_mount = true
    for part_name in ["Torso", "Head", "LeftLeg", "RightLeg", "LeftArm", "RightArm"]:
        var primitive := avatar.get_node_or_null(part_name) as Node3D
        if primitive != null:
            primitive.visible = false
    _play_jaime_animation("idle")

func _play_jaime_animation(clip_name: String) -> void:
    if jaime_animation == null:
        return
    var chosen := ""
    for animation_name in jaime_animation.get_animation_list():
        if String(animation_name).to_lower().get_slice("/", String(animation_name).get_slice_count("/") - 1) == clip_name:
            chosen = String(animation_name)
            break
    if chosen == "":
        for library_name in jaime_animation.get_animation_library_list():
            var library := jaime_animation.get_animation_library(library_name)
            for animation_name in library.get_animation_list():
                if String(animation_name).to_lower() == clip_name:
                    chosen = String(library_name) + "/" + String(animation_name) if String(library_name) != "" else String(animation_name)
                    break
            if chosen != "":
                break
    if chosen != "" and chosen != jaime_animation_name:
        jaime_animation_name = chosen
        jaime_animation.play(chosen, 0.16)

var shoulder_side := 1.0

func swap_shoulder() -> void:
    shoulder_side = -shoulder_side

func is_scope_active() -> bool:
    return not has_bow() and not weapon_holstered and current_weapon == "sniper" and aiming and not reloading

## Põe (id do item) ou tira ("") o escudo do braço esquerdo.
func set_shield(id: String) -> void:
    if id != shield_id:
        shield_raised = false
    shield_id = id

## Botão FIXA: levanta / abaixa a guarda do escudo.
func toggle_shield_guard() -> void:
    if shield_id.is_empty() or swimming or prone or climbing or has_bow():
        shield_raised = false
        return
    shield_raised = not shield_raised

func _unhandled_input(event: InputEvent) -> void:
    if fishing_active and not event is InputEventMouseMotion:
        return
    if event is InputEventMouseButton and event.pressed and is_scope_active():
        if event.button_index == MOUSE_BUTTON_WHEEL_UP:
            scope_zoom = clampf(scope_zoom + 1.0, 4.0, 8.0)
            return
        if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            scope_zoom = clampf(scope_zoom - 1.0, 4.0, 8.0)
            return
    # Teclas configuráveis (Configurações › Controles): tudo passa pelas ações.
    # InputEventAction: os botões de toque apertam as mesmas ações.
    if (event is InputEventKey or event is InputEventMouseButton or event is InputEventAction) and event.is_pressed() and not event.is_echo():
        if event.is_action("shoulder_swap"):
            if PointerMode.is_captured() and not (ui_blocking.is_valid() and bool(ui_blocking.call())):
                swap_shoulder()
            return
        if event.is_action("shield"):
            if PointerMode.is_captured() and not (ui_blocking.is_valid() and bool(ui_blocking.call())):
                toggle_shield_guard()
            return
        if climbing and (event.is_action("grenade") or event.is_action("interact") or event.is_action("heal")):
            return # mãos ocupadas na escalada
        if aiming and (event.is_action("lean_left") or event.is_action("lean_right")):
            return # while aiming, the lean keys lean (handled every physics frame)
        if event.is_action("grenade"):
            if has_bow():
                bow_controller.call("unequip")
            if not grenade_aiming and _can_start_grenade_aim():
                grenade_aiming = true
            return
        if event.is_action("interact"):
            # Collects loot when a crate is in reach; otherwise elbow strike.
            if interact_handler.is_valid() and bool(interact_handler.call()):
                return
            if humanoid_avatar != null and humanoid_avatar.has_method("play_action"):
                face_aim(0.6)
                humanoid_avatar.call("play_action", "elbow_punch")
            return
        if event.is_action("heal"):
            if heal_handler.is_valid():
                heal_handler.call()
            return
        if event.is_action("holster"):
            if has_bow():
                bow_controller.call("unequip")
                return
            if current_weapon == "bow" and (not loadout_limited or owned_weapons.has("bow")):
                bow_controller.call("equip")
                return
            if not loadout_limited or not owned_weapons.is_empty():
                _toggle_weapon_holster()
            elif not melee_weapon.is_empty():
                melee_weapon = "" # só arma branca: H guarda e fica de mãos vazias
            return
        var slots := ["rifle", "sniper", "pistol", "shotgun", "smg", "bow"]
        for index in slots.size():
            if not event.is_action("weapon_%d" % (index + 1)):
                continue
            var slot: String = slots[index]
            if loadout_limited:
                if index >= slot_order.size():
                    return
                slot = slot_order[index]
                if melee_slots.has(slot):
                    select_melee(slot)
                    return
            melee_weapon = "" # pegou a arma de fogo: larga a arma branca
            if has_bow():
                bow_controller.call("unequip")
            _equip_weapon(slot)
            if weapon_holstered and slot != "bow":
                _toggle_weapon_holster()
            return
    if event.is_action_released("grenade") and grenade_aiming:
        _release_grenade()
        return
    if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
        if has_bow():
            bow_controller.call("cancel_draw")
        cancel_grenade_aim()
        Input.action_release("aim")
        aiming = false
        PointerMode.release()
    if event is InputEventMouseButton and event.pressed and not PointerMode.is_captured():
        # Com a mochila (ou outra janela) aberta o clique é para ela: o cursor fica.
        if ui_blocking.is_valid() and bool(ui_blocking.call()):
            return
        PointerMode.capture()
    if event is InputEventMouseMotion and PointerMode.is_captured():
        _apply_mouse_look(event.relative)

func _apply_mouse_look(relative: Vector2) -> void:
    var sensitivity := mouse_sensitivity / scope_zoom if is_scope_active() else mouse_sensitivity
    if first_person_view and not is_scope_active():
        # Same screen-relative speed as the hip view: scale by the FOV ratio.
        var ratio := tan(deg_to_rad(camera.fov) * 0.5) / tan(deg_to_rad(BASE_FOV) * 0.5)
        sensitivity *= lerpf(1.0, ratio, ads_sensitivity_scale)
    var previous := Vector2(yaw, pitch)
    yaw -= relative.x * sensitivity
    pitch = clampf(pitch - relative.y * sensitivity, -1.15, 0.95)
    _look_delta += Vector2(yaw, pitch) - previous

## First-person ADS FOV for the current weapon.
func first_person_fov() -> float:
    var zoom: float = ADS_ZOOM.get(current_weapon, 1.15)
    return rad_to_deg(2.0 * atan(tan(deg_to_rad(BASE_FOV) * 0.5) / zoom))

func _can_stand() -> bool:
    var query := PhysicsShapeQueryParameters3D.new()
    query.shape = standing_probe
    query.collision_mask = collision_mask
    query.exclude = [get_rid()]
    # Lift the probe just above floor contact, retaining conservative head clearance.
    query.transform = global_transform
    query.transform.origin += global_basis.y * (height * 0.5 + 0.005)
    return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

## Ctrl alterna a postura: 1º toque agacha, 2º deita, 3º levanta (fica na
## posição sem segurar). Espaço ou Shift levantam direto. Sob um teto baixo
## continua abaixado até ter espaço.
func _update_crouch(delta: float) -> void:
    stance_changed = false
    if Input.is_action_just_pressed("crouch"):
        stance = (stance + 1) % 3
        stance_changed = true
    elif stance > 0 and (Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("sprint")):
        stance = 0
        stance_changed = true
    var blocked := stance == 0 and body_capsule.height < height - 0.001 and not _can_stand()
    prone = stance == 2
    crouching = stance == 1 or blocked
    var target_height := height
    if prone:
        target_height = body_capsule.radius * 2.0
    elif crouching:
        target_height = maxf(body_capsule.radius * 2.0, height * 0.86)
    body_capsule.height = move_toward(body_capsule.height, target_height, delta * 3.0)
    # Preserve the foot origin through every intermediate capsule size.
    body_collision.position.y = body_capsule.height * 0.5

func _physics_process(delta: float) -> void:
    aiming = not fishing_active and bool(bow_controller.get("draw").drawing) if has_bow() else (not fishing_active and has_sights() and Input.is_action_pressed("aim"))
    _update_crouch(delta)
    rotation.y = yaw
    arm_pivot.rotation.x = pitch
    _grenade_cooldown = maxf(0.0, _grenade_cooldown - delta)
    _update_lean(delta)
    if channel_left > 0.0:
        channel_left -= delta
        if channel_left <= 0.0:
            channel_left = 0.0
            var done := _channel_done
            _channel_done = Callable()
            if done.is_valid():
                done.call()
    var scoped := is_scope_active()
    var wants_first_person := aiming and not scoped and not has_bow()
    var desired_fov := first_person_fov() if wants_first_person else BASE_FOV
    if scoped:
        desired_fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(BASE_FOV) * 0.5) / scope_zoom))
    # Closing the optic restores the shoulder frame before showing the body.
    camera.fov = desired_fov if scope_was_active and not scoped else lerpf(camera.fov, desired_fov, 1.0 - exp(-delta * 14.0))
    scope_was_active = scoped
    hit_shake = move_toward(hit_shake, 0.0, delta * 3.5)
    _land_dip = move_toward(_land_dip, 0.0, delta * 1.6)
    camera.h_offset = randf_range(-1.0, 1.0) * hit_shake * 0.06
    camera.v_offset = randf_range(-1.0, 1.0) * hit_shake * 0.06 - _land_dip
    var spring: SpringArm3D = camera.get_parent()
    var camera_blend := minf(1, delta * 16)
    spring.spring_length = lerpf(spring.spring_length, 0.0 if wants_first_person else (2.15 if aiming else cam_distance), camera_blend)
    # O ombro fica 1 m para o lado; encostado numa parede esse ponto já estaria do
    # outro lado dela (dava para ver através). Limita pelo espaço livre, na hora.
    var shoulder := 0.0 if wants_first_person else shoulder_side
    spring.position.x = _shoulder_room(lerpf(spring.position.x, shoulder, camera_blend))
    var eye_height := height * (0.24 if prone else (0.62 if crouching else 0.92))
    var shoulder_height := height * (0.30 if prone else (0.59 if crouching else 0.86))
    arm_pivot.position.y = lerpf(arm_pivot.position.y, eye_height if wants_first_person else shoulder_height, minf(1,delta * 12))
    # The body hides once the camera is inside the head; the viewmodel replaces it.
    first_person_view = wants_first_person and spring.spring_length < FIRST_PERSON_CUTOFF
    avatar.visible = not scoped and not first_person_view
    viewmodel.visible = first_person_view
    var crouch_offset := 0.0 # Feet stay anchored; crouch belongs to the rig and capsule.
    avatar.position.y = lerpf(avatar.position.y, crouch_offset if crouching else 0.0, minf(1,delta * 10))
    if climbing:
        _update_climb(delta)
        return
    var input_vec := Input.get_vector("move_left","move_right","move_forward","move_back")
    var movement := Vector3(input_vec.x,0,input_vec.y).rotated(Vector3.UP,yaw)
    var walking := InputMap.has_action("walk") and Input.is_action_pressed("walk") and not Input.is_action_pressed("sprint")
    var water: Dictionary = water_query.call(global_position) if water_query.is_valid() else {}
    swimming = not water.is_empty() and float(water.get("surface", -100)) - global_position.y > 0.75
    var current_speed: float = PRONE_SPEED if prone else (CROUCH_SPEED if crouching else (speed * sprint_multiplier if Input.is_action_pressed("sprint") and not aiming else (WALK_SPEED if walking else speed)))
    if swimming: current_speed = minf(current_speed, 2.6)
    if shield_raised:
        if swimming or prone or climbing or has_bow():
            shield_raised = false # mãos ocupadas: a guarda cai
        else:
            current_speed = minf(current_speed, SHIELD_GUARD_SPEED)
    current_speed *= 1.0 - LAND_SLOWDOWN * clampf(_land_recovery / LAND_RECOVERY_TIME, 0.0, 1.0)
    _land_recovery = maxf(0.0, _land_recovery - delta)
    var grounded_before := is_on_floor()
    var horizontal := Vector2(velocity.x, velocity.z)
    var desired_velocity := Vector2(movement.x, movement.z) * current_speed
    var rate := deceleration if desired_velocity.length_squared() < horizontal.length_squared() or horizontal.dot(desired_velocity) < 0.0 else acceleration
    if not grounded_before:
        # No ar o impulso do pulo se mantém: só um pouco de correção, sem frear.
        rate = acceleration * AIR_CONTROL if desired_velocity.length_squared() > 0.01 else 0.0
    horizontal = horizontal.move_toward(desired_velocity, rate * delta)
    velocity.x = horizontal.x
    velocity.z = horizontal.y
    # Pulo tolerante: vale apertar um pouco antes de tocar o chão (buffer) e um
    # pouco depois de sair da beirada (coyote time).
    _coyote_left = COYOTE_TIME if grounded_before else maxf(0.0, _coyote_left - delta)
    _jump_buffer_left = maxf(0.0, _jump_buffer_left - delta)
    if Input.is_action_just_pressed("jump") and not stance_changed:
        _jump_buffer_left = JUMP_BUFFER_TIME
    if grounded_before:
        _last_floor_y = global_position.y
    # Escalada: espaço de frente para uma borda alta (no chão), ou segurando a
    # direção contra ela no ar (perto do topo do pulo ou caindo).
    var climb_ok := not crouching and not prone and not stance_changed
    if climb_ok and _jump_buffer_left > 0.0 and grounded_before and _try_climb(movement, true):
        _jump_buffer_left = 0.0
        return
    if climb_ok and not grounded_before and input_vec.length() > 0.3 and velocity.y < CLIMB_AIR_MAX_UP_SPEED and _try_climb(movement, false):
        _jump_buffer_left = 0.0
        return
    var can_jump := _coyote_left > 0.0 and not crouching and not prone and velocity.y <= 0.5
    if _jump_buffer_left > 0.0 and can_jump:
        velocity.y = jump_velocity
        _jump_buffer_left = 0.0
        _coyote_left = 0.0
    elif not grounded_before:
        velocity.y -= float(ProjectSettings.get_setting("physics/3d/default_gravity")) * delta
    else:
        velocity.y = -0.1
    if swimming:
        var target_y := float(water.surface) - height * 0.58
        velocity.y = clampf((target_y - global_position.y) * 4.0, -3.0, 3.0)
        _jump_buffer_left = 0.0
        if channel_left > 0.0: cancel_channel()
    var fall_speed := 0.0 if swimming else -velocity.y
    move_and_slide()
    if is_on_floor() and not grounded_before:
        _on_landed(fall_speed)
    var actual_velocity := get_real_velocity()
    _update_body_facing(delta, actual_velocity)
    var actual_move := clampf(Vector2(actual_velocity.x, actual_velocity.z).length() / maxf(current_speed, 0.01), 0.0, 1.0)
    sprinting = Input.is_action_pressed("sprint") and not aiming and not shield_raised and not crouching and not prone and actual_velocity.slide(Vector3.UP).length() > speed + 0.2 and input_vec.length() > 0.1
    _animate_avatar(delta, actual_move, is_on_floor())
    fire_delay = maxf(0, fire_delay - delta)
    gun_flash.light_energy = move_toward(gun_flash.light_energy, 0.0, delta * 55.0)
    muzzle_flare.visible = gun_flash.light_energy > 0.05
    # Luz apagada fica invisível: senão tudo perto do jogador calcula essa luz.
    gun_flash.visible = gun_flash.light_energy > 0.0
    gun_kick = move_toward(gun_kick, 0.0, delta * 5.0)
    # Presentation-only animation: never changes projectile aim or character movement.
    var movement_weight := clampf(input_vec.length(), 0.0, 1.0)
    if is_on_floor() and movement_weight > 0.1:
        locomotion_clock += delta * (13.0 if Input.is_action_pressed("sprint") else 8.5)
    var bob := sin(locomotion_clock) * 0.018 * movement_weight if is_on_floor() else 0.0
    var desired_offset := Vector3(-0.045, 0.025, 0.07) if aiming else Vector3.ZERO
    presentation_offset = presentation_offset.lerp(desired_offset, minf(delta * 12.0, 1.0))
    if gun_uses_model_mount:
        gun.position = Vector3(0.0, 0.0, gun_kick * 0.3)
        gun.rotation.x = 0.0
    else:
        gun.position = Vector3(0.33, 1.28 + bob, -0.48 + gun_kick) + presentation_offset
        gun.rotation.x = lerpf(gun.rotation.x, -0.065 if aiming else 0.0, minf(delta * 10.0, 1.0))
    if humanoid_avatar != null and humanoid_avatar.has_method("refresh_weapon_grip"):
        humanoid_avatar.call("refresh_weapon_grip")
    if first_person_view:
        viewmodel.call("animate", delta, gun_kick, bob * 0.5, muzzle_flare.visible, reloading, _first_person_clearance(), _look_delta)
    _look_delta = Vector2.ZERO
    if reloading:
        reload_timer -= delta
        if reload_timer <= 0:
            var stats: Dictionary = WeaponData.stats(current_weapon)
            var missing: int = int(stats["mag"]) - ammo
            var supplied: int = mini(missing, int(reserve_ammo[current_weapon]))
            ammo += supplied
            reserve_ammo[current_weapon] -= supplied
            magazines[current_weapon] = ammo
            reloading = false
    if not weapon_holstered and Input.is_action_just_pressed("reload") and ammo < int(WeaponData.stats(current_weapon)["mag"]) and not reloading and int(reserve_ammo[current_weapon]) > 0:
        _reload()
    if fishing_active:
        pass # fishing owns combat inputs
    elif swimming:
        pass # nadando: as mãos estão na braçada (sem tiro nem golpe)
    elif has_bow():
        pass # bow_controller fires only on release, never through the gun/melee paths
    elif not melee_weapon.is_empty():
        # Bastão na mão: clique esquerdo golpeia (um golpe por clique).
        if not grenade_aiming and Input.is_action_just_pressed("fire") and PointerMode.is_captured() and channel_left <= 0.0 and melee_handler.is_valid():
            melee_handler.call()
    elif weapon_holstered:
        # Mãos vazias: clique esquerdo dá soco (ou golpe com a arma branca da mochila).
        if not grenade_aiming and not attack_blocked and not climbing and Input.is_action_just_pressed("fire") and PointerMode.is_captured() and channel_left <= 0.0:
            _punch()
    elif not weapon_holstered and not grenade_aiming and Input.is_action_pressed("fire") and PointerMode.is_captured() and fire_delay <= 0 and not reloading and channel_left <= 0.0:
        _shoot()
    if grenade_aiming:
        if not Input.is_action_pressed("grenade"):
            cancel_grenade_aim() # the release was lost (focus change, menu); never throw by accident
        else:
            _update_grenade_preview()

## Com arma branca na mão o corpo não anda de lado: vira para onde está
## andando (estilo mundo aberto clássico) e sempre caminha para a frente. A
## câmera e a mira continuam livres. Ao golpear (face_aim) vira rápido para a
## mira, para o golpe sair onde se aponta. Com arma de fogo, o corpo segue a
## câmera como antes (passos laterais de quem mira).
const BODY_TURN_RATE := 10.0
const BODY_AIM_TURN_RATE := 28.0
var _body_yaw := 0.0
var _face_aim_left := 0.0

## Sensação de movimento (estilo do Game Animation Sample): pulo tolerante,
## pouco controle no ar, aterrissagem com peso e corpo inclinando nas curvas.
const COYOTE_TIME := 0.12 # ainda pula logo depois de sair da beirada
const JUMP_BUFFER_TIME := 0.12 # espaço apertado um pouco antes de tocar o chão vale
const AIR_CONTROL := 0.35 # fração da aceleração no chão disponível no ar
const LAND_MIN_SPEED := 5.5 # queda mais lenta que isso não tem impacto
const LAND_HARD_SPEED := 14.0 # queda que dá o impacto máximo
const LAND_RECOVERY_TIME := 0.35
const LAND_SLOWDOWN := 0.45 # perde até 45% da velocidade logo após uma queda forte
const TURN_LEAN_MAX := 0.12 # inclinação máxima do corpo (rad) ao fazer curva correndo
var _coyote_left := 0.0
var _jump_buffer_left := 0.0
var _land_recovery := 0.0
var _land_dip := 0.0
var turn_lean := 0.0
var last_landing_strength := 0.0

func _on_landed(fall_speed: float) -> void:
    if fall_speed < LAND_MIN_SPEED:
        return
    var strength := clampf((fall_speed - LAND_MIN_SPEED) / (LAND_HARD_SPEED - LAND_MIN_SPEED), 0.0, 1.0)
    last_landing_strength = strength
    _land_dip = maxf(_land_dip, lerpf(0.05, 0.22, strength))
    _land_recovery = LAND_RECOVERY_TIME * strength
    if sound_fx != null and sound_fx.has_method("landing"):
        sound_fx.call("landing", strength)

## Escalada: sobe em bordas mais altas que o pulo (muro, caixote, laje) com o
## clipe ClimbUp_1m da Universal Animation Library 2. A cápsula segue uma curva
## (sobe, depois avança por cima da borda) e o clipe mexe braços e pernas; o
## quadril do clipe não sobe junto (o corpo já sobe com a cápsula).
const CLIMB_GROUND_MIN := 1.25 # abaixo disso o pulo normal já resolve
const CLIMB_MAX := 2.5 # topo mais alto que as mãos alcançam (a partir do chão)
const CLIMB_AIR_MIN := 0.5 # no ar: topo pelo menos isto acima dos pés
const CLIMB_AIR_MAX_UP_SPEED := 3.0 # no ar, só perto do topo do pulo ou caindo
const CLIMB_REACH := 0.7 # distância da parede (além do raio da cápsula)
const CLIMB_TIME_LOW := 0.8 # segundos para subir ~1 m
const CLIMB_TIME_HIGH := 1.25 # segundos para subir 2,5 m
const CLIMB_CLIP := "climbup_1m"
const CLIMB_HUG := 0.2 # centro do corpo a esta distância da parede durante a subida
var climbing := false
var _climb_hug := Vector3.ZERO
var last_climb_height := 0.0
var _climb_t := 0.0
var _climb_time := 1.0
var _climb_from := Vector3.ZERO
var _climb_to := Vector3.ZERO
var _climb_yaw := 0.0
var _last_floor_y := 0.0

## Borda escalável na direção `dir` (horizontal): {target, rise, normal} ou {}.
## `rise_min`/`rise_max` são a altura do topo em relação aos pés agora.
func find_climb_ledge(dir: Vector3, rise_min: float, rise_max: float) -> Dictionary:
    dir.y = 0.0
    if dir.length_squared() < 0.0001 or body_capsule == null:
        return {}
    dir = dir.normalized()
    var space := get_world_3d().direct_space_state
    var feet := global_position
    var radius := body_capsule.radius
    var exclude: Array[RID] = [get_rid()]
    # 1) Parede à frente (raios em alturas diferentes: muro baixo ou alto).
    var wall := {}
    for h in [0.35, 0.8, 1.3]:
        if h >= rise_max:
            break
        var from: Vector3 = feet + Vector3.UP * h
        var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + dir * (radius + CLIMB_REACH), collision_mask, exclude))
        if not hit.is_empty() and absf((hit["normal"] as Vector3).y) < 0.35:
            wall = hit
            break
    if wall.is_empty():
        return {}
    var normal: Vector3 = wall["normal"]
    normal.y = 0.0
    normal = normal.normalized()
    # De frente para a parede (não escala andando de lado colado nela).
    if dir.dot(-normal) < 0.5:
        return {}
    var probe: Vector3 = (wall["position"] as Vector3) - normal * (radius + 0.08)
    var top_y := feet.y + rise_max + 0.3
    # 2) Acima da borda está livre (o muro termina antes do alcance, sem marquise).
    var over_from := Vector3(feet.x, top_y, feet.z)
    if not space.intersect_ray(PhysicsRayQueryParameters3D.create(over_from, Vector3(probe.x, top_y, probe.z), collision_mask, exclude)).is_empty():
        return {}
    # 3) Topo plano da borda.
    var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(probe.x, top_y, probe.z), Vector3(probe.x, feet.y + rise_min, probe.z), collision_mask, exclude))
    if down.is_empty() or (down["normal"] as Vector3).y < 0.75:
        return {}
    var ledge_y: float = (down["position"] as Vector3).y
    var rise := ledge_y - feet.y
    if rise < rise_min or rise > rise_max:
        return {}
    # 4) Cabe em pé lá em cima e há espaço para subir sem bater a cabeça.
    var target := Vector3(probe.x, ledge_y + 0.02, probe.z)
    var query := PhysicsShapeQueryParameters3D.new()
    query.shape = standing_probe
    query.collision_mask = collision_mask
    query.exclude = exclude
    query.transform = Transform3D(Basis.IDENTITY, target + Vector3.UP * (height * 0.5 + 0.03))
    if not space.intersect_shape(query, 1).is_empty():
        return {}
    var head := feet + Vector3.UP * (body_capsule.height - 0.05)
    if not space.intersect_ray(PhysicsRayQueryParameters3D.create(head, Vector3(feet.x, ledge_y + height, feet.z), collision_mask, exclude)).is_empty():
        return {}
    return {"target": target, "rise": rise, "normal": normal, "wall": wall["position"]}

func _try_climb(movement: Vector3, on_ground: bool) -> bool:
    if climbing or channel_left > 0.0:
        return false
    var dir := movement
    if dir.length_squared() < 0.01:
        if not on_ground:
            return false
        dir = Vector3.FORWARD.rotated(Vector3.UP, _body_yaw) # parado: para onde o corpo olha
    var ledge := {}
    if on_ground:
        ledge = find_climb_ledge(dir, CLIMB_GROUND_MIN, CLIMB_MAX)
    else:
        # No ar o alcance continua contado a partir do último chão.
        var reach := CLIMB_MAX - (global_position.y - _last_floor_y)
        if reach > CLIMB_AIR_MIN:
            ledge = find_climb_ledge(dir, CLIMB_AIR_MIN, reach)
    if ledge.is_empty():
        return false
    start_climb(ledge)
    return true

func start_climb(ledge: Dictionary) -> void:
    if has_bow():
        bow_controller.call("unequip")
    climbing = true
    _climb_t = 0.0
    _climb_from = global_position
    _climb_to = ledge["target"]
    var normal: Vector3 = ledge["normal"]
    _climb_hug = Vector3(ledge["wall"].x, _climb_from.y, ledge["wall"].z) + normal * CLIMB_HUG
    # Já mais perto que isso: não recua.
    if (_climb_from - _climb_hug).dot(normal) < 0.0:
        _climb_hug = _climb_from
    _climb_yaw = atan2(normal.x, normal.z) # frente do corpo (-Z) para dentro da parede
    var total_rise := _climb_to.y - _last_floor_y if not is_on_floor() else float(ledge["rise"])
    last_climb_height = float(ledge["rise"])
    _climb_time = lerpf(CLIMB_TIME_LOW, CLIMB_TIME_HIGH, clampf((total_rise - 1.0) / (CLIMB_MAX - 1.0), 0.0, 1.0))
    if not is_on_floor():
        _climb_time *= 0.85 # já pendurado no alto do pulo: só o puxão final
    velocity = Vector3.ZERO
    _coyote_left = 0.0
    if grenade_aiming:
        cancel_grenade_aim()
    Input.action_release("aim")
    aiming = false
    if humanoid_avatar != null and humanoid_avatar.has_method("play_climb"):
        humanoid_avatar.call("play_climb", CLIMB_CLIP, _climb_time)
    if sound_fx != null and sound_fx.has_method("landing"):
        sound_fx.call("landing", 0.15) # mãos batendo na borda

func _update_climb(delta: float) -> void:
    _climb_t = minf(_climb_t + delta / maxf(_climb_time, 0.05), 1.0)
    # O ClimbUp_1m é "no lugar" (o quadril sobe só 0,25 m e volta): quem sobe
    # é a cápsula. Ela chega ao topo só quando o clipe estica as pernas em cima
    # da borda (~80%); antes disso os joelhos encolhidos ficam rente à quina.
    # Depois o corpo passa por cima da borda.
    var up := 1.0 - pow(1.0 - clampf(_climb_t / 0.8, 0.0, 1.0), 1.6)
    # Encosta na parede no começo (o peito rente ao muro, como quem se pendura)
    # e passa por cima da borda no fim.
    var pos := _climb_from.lerp(_climb_hug, smoothstep(0.0, 0.3, _climb_t)).lerp(_climb_to, smoothstep(0.55, 1.0, _climb_t))
    pos.y = lerpf(_climb_from.y, _climb_to.y, up)
    global_position = pos
    velocity = Vector3.ZERO
    _body_yaw = lerp_angle(_body_yaw, _climb_yaw, minf(1.0, delta * 18.0))
    if avatar != null:
        avatar.rotation.y = wrapf(_body_yaw - yaw, -PI, PI)
        turn_lean = 0.0
        avatar.rotation.z = 0.0
    _animate_avatar(delta, 0.0, true)
    _look_delta = Vector2.ZERO
    if _climb_t >= 1.0:
        climbing = false
        global_position = _climb_to
        _last_floor_y = _climb_to.y
        _coyote_left = 0.0
        _jump_buffer_left = 0.0
        velocity = Vector3(0.0, -0.1, 0.0)
        # Ainda encostado no topo: deixa o corpo assentar no chão novo.
        move_and_slide()
        if sound_fx != null and sound_fx.has_method("landing"):
            sound_fx.call("landing", 0.1)

func face_aim(seconds: float) -> void:
    _face_aim_left = maxf(_face_aim_left, seconds)

## Para onde o corpo olha (vai para a rede: os outros veem o corpo de frente
## para onde ele corre, não andando de lado).
func network_yaw() -> float:
    return _body_yaw

func _update_body_facing(delta: float, planar_velocity: Vector3) -> void:
    if avatar == null:
        return
    _face_aim_left = maxf(0.0, _face_aim_left - delta)
    # Livre com arma branca ou de mãos vazias (arma guardada); com arma de
    # fogo na mão ou mirando, o corpo segue a câmera.
    var free_facing := (not melee_weapon.is_empty() or weapon_holstered) and not aiming and not prone and not grenade_aiming
    if not free_facing:
        _body_yaw = yaw
        avatar.rotation.y = 0.0
        turn_lean = lerpf(turn_lean, 0.0, minf(1.0, delta * 10.0))
        avatar.rotation.z = turn_lean
        return
    var planar := Vector2(planar_velocity.x, planar_velocity.z)
    var rate := BODY_TURN_RATE
    var target := _body_yaw
    if _face_aim_left > 0.0:
        target = yaw
        rate = BODY_AIM_TURN_RATE
    elif planar.length() > 0.4:
        target = atan2(-planar.x, -planar.y) # frente do corpo = -Z
    var previous_yaw := _body_yaw
    _body_yaw = lerp_angle(_body_yaw, target, minf(1.0, delta * rate))
    # Inclina para dentro da curva, mais forte quanto mais rápido e mais fechada.
    var turn_speed := wrapf(_body_yaw - previous_yaw, -PI, PI) / maxf(delta, 0.0001)
    var speed_factor := clampf(planar.length() / (speed * sprint_multiplier), 0.0, 1.0)
    var lean_target := 0.0
    if is_on_floor() and not crouching:
        lean_target = clampf(turn_speed * 0.05 * speed_factor, -TURN_LEAN_MAX, TURN_LEAN_MAX)
    turn_lean = lerpf(turn_lean, lean_target, minf(1.0, delta * 8.0))
    avatar.rotation.z = turn_lean
    # O avatar é filho do jogador (que gira com a câmera): rotação relativa.
    avatar.rotation.y = wrapf(_body_yaw - yaw, -PI, PI)

func _toggle_weapon_holster() -> void:
    weapon_holstered = not weapon_holstered
    if not weapon_holstered:
        melee_weapon = "" # sacou a arma de fogo: larga a arma branca
    aiming = false
    Input.action_release("aim")
    if weapon_holstered:
        reloading = false
        reload_timer = 0.0
        gun_kick = 0.0
        if gun_flash != null:
            gun_flash.light_energy = 0.0
        if muzzle_flare != null:
            muzzle_flare.visible = false
        if sound_fx != null and sound_fx.has_node("ReloadAudio"):
            (sound_fx.get_node("ReloadAudio") as AudioStreamPlayer).stop()
    if weapon_model != null:
        weapon_model.visible = not weapon_holstered
    if humanoid_avatar != null and humanoid_avatar.has_method("set_armed"):
        humanoid_avatar.call("set_armed", not weapon_holstered)
        if not weapon_holstered and humanoid_avatar.has_method("refresh_weapon_grip"):
            humanoid_avatar.call("refresh_weapon_grip")

## Throw a grenade from the eye along the view; returns it (caller wires online/offline).
func throw_grenade(grenade_id: String) -> RigidBody3D:
    var grenade: RigidBody3D = GrenadeScript.new()
    grenade.set("grenade_id", grenade_id)
    var forward := -camera.global_basis.z
    get_tree().current_scene.add_child(grenade)
    grenade.global_position = grenade_launch_origin()
    grenade.linear_velocity = GrenadeScript.throw_velocity(forward, velocity)
    grenade.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
    if humanoid_avatar != null and humanoid_avatar.has_method("play_action"):
        # Overhand throw over the legs (UAL2); older adapters fall back to the elbow swing.
        if not bool(humanoid_avatar.call("play_action", "throw")):
            humanoid_avatar.call("play_action", "elbow_punch")
    return grenade

func grenade_launch_origin() -> Vector3:
    return camera.global_position - camera.global_basis.z * 0.6

func _can_start_grenade_aim() -> bool:
    if grenade_check.is_valid():
        return bool(grenade_check.call())
    return grenade_handler.is_valid() or _grenade_cooldown <= 0.0

func _release_grenade() -> void:
    cancel_grenade_aim()
    if grenade_handler.is_valid():
        grenade_handler.call()
    elif _grenade_cooldown <= 0.0:
        _grenade_cooldown = 1.0
        var grenade := throw_grenade("")
        grenade.set("offline_damage", true)

func cancel_grenade_aim() -> void:
    grenade_aiming = false
    if _grenade_preview != null:
        _grenade_preview.visible = false

func _exit_tree() -> void:
    if _grenade_preview != null and is_instance_valid(_grenade_preview):
        _grenade_preview.queue_free()

## Draws the predicted arc (dots), where it first touches something (small mark) and
## the blast circle (GrenadeScript.RADIUS) where it will explode when the fuse ends.
func _update_grenade_preview() -> void:
    if _grenade_preview == null or not is_instance_valid(_grenade_preview):
        _build_grenade_preview()
    var forward := -camera.global_basis.z
    var result := GrenadeScript.predict_path(get_world_3d().direct_space_state, grenade_launch_origin(), GrenadeScript.throw_velocity(forward, velocity), [get_rid()])
    var points: PackedVector3Array = result["points"]
    var multimesh := _grenade_dots.multimesh
    var stride := maxi(1, int(ceil(float(points.size()) / GRENADE_PREVIEW_DOTS)))
    var shown := 0
    var index := 2 # skip the first points: they sit right in front of the camera
    while index < points.size() and shown < GRENADE_PREVIEW_DOTS:
        multimesh.set_instance_transform(shown, Transform3D(Basis(), points[index]))
        shown += 1
        index += stride
    multimesh.visible_instance_count = shown
    _grenade_impact.visible = bool(result["has_hit"])
    _grenade_impact.global_position = result["first_hit"]
    var end: Vector3 = result["end"]
    var normal: Vector3 = result["end_normal"]
    _grenade_ring.global_transform = Transform3D(_basis_from_up(normal), end + normal * 0.06)
    _grenade_preview.visible = true

static func _basis_from_up(up: Vector3) -> Basis:
    var y := up.normalized()
    var side := Vector3.RIGHT if absf(y.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
    var z := side.cross(y).normalized()
    var x := y.cross(z).normalized()
    return Basis(x, y, z)

func _build_grenade_preview() -> void:
    _grenade_preview = Node3D.new()
    _grenade_preview.name = "GrenadeAimPreview"
    _grenade_preview.top_level = true
    get_tree().current_scene.add_child(_grenade_preview)
    var dot_material := StandardMaterial3D.new()
    dot_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    dot_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    dot_material.no_depth_test = true
    dot_material.albedo_color = Color(1.0, 0.82, 0.35, 0.85)
    var dot_mesh := SphereMesh.new()
    dot_mesh.radius = 0.045
    dot_mesh.height = 0.09
    dot_mesh.radial_segments = 8
    dot_mesh.rings = 4
    dot_mesh.material = dot_material
    var multimesh := MultiMesh.new()
    multimesh.transform_format = MultiMesh.TRANSFORM_3D
    multimesh.mesh = dot_mesh
    multimesh.instance_count = GRENADE_PREVIEW_DOTS
    multimesh.visible_instance_count = 0
    _grenade_dots = MultiMeshInstance3D.new()
    _grenade_dots.multimesh = multimesh
    _grenade_dots.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    _grenade_preview.add_child(_grenade_dots)
    var impact_mesh := SphereMesh.new()
    impact_mesh.radius = 0.12
    impact_mesh.height = 0.24
    impact_mesh.material = dot_material
    _grenade_impact = MeshInstance3D.new()
    _grenade_impact.mesh = impact_mesh
    _grenade_impact.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    _grenade_preview.add_child(_grenade_impact)
    var ring_material := StandardMaterial3D.new()
    ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    ring_material.no_depth_test = true
    ring_material.albedo_color = Color(1.0, 0.3, 0.2, 0.75)
    var ring_mesh := TorusMesh.new()
    ring_mesh.outer_radius = GrenadeScript.RADIUS
    ring_mesh.inner_radius = GrenadeScript.RADIUS - 0.12
    ring_mesh.rings = 64
    ring_mesh.ring_segments = 4
    ring_mesh.material = ring_material
    _grenade_ring = MeshInstance3D.new()
    _grenade_ring.mesh = ring_mesh
    _grenade_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    _grenade_preview.add_child(_grenade_ring)
    var center_mesh := CylinderMesh.new()
    center_mesh.top_radius = 0.35
    center_mesh.bottom_radius = 0.35
    center_mesh.height = 0.02
    center_mesh.material = ring_material
    var center := MeshInstance3D.new()
    center.mesh = center_mesh
    center.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    _grenade_ring.add_child(center)

## Espaço livre ao lado da cabeça (para a câmera de ombro), sem entrar em paredes.
func _shoulder_room(wanted: float) -> float:
    var from := arm_pivot.global_position
    var to := arm_pivot.global_transform * Vector3(wanted, 0, 0)
    var query := PhysicsShapeQueryParameters3D.new()
    var probe := SphereShape3D.new()
    probe.radius = 0.22
    query.shape = probe
    query.collision_mask = HitboxScript.LAYER_WORLD
    query.exclude = [get_rid()]
    query.transform = Transform3D(Basis.IDENTITY, from)
    query.motion = to - from
    var space := get_world_3d().direct_space_state
    # Começou dentro de algo (cabeça colada na parede): sem deslocamento lateral.
    if not space.intersect_shape(query, 1).is_empty():
        return 0.0
    var safe: float = space.cast_motion(query)[0]
    return wanted * clampf(safe, 0.0, 1.0)

## Lean: slide the view sideways and roll it, limited by walls beside the head.
func _update_lean(delta: float) -> void:
    var target := 0.0
    if aiming and not reloading and not weapon_holstered:
        if Input.is_action_pressed("lean_left"):
            target -= 1.0
        if Input.is_action_pressed("lean_right"):
            target += 1.0
    lean = move_toward(lean, target, delta * 5.0)
    var reach := LEAN_DISTANCE
    if absf(lean) > 0.01:
        var eye := global_position + Vector3(0, arm_pivot.position.y, 0)
        var side := global_basis.x * signf(lean)
        var query := PhysicsRayQueryParameters3D.create(eye, eye + side * (LEAN_DISTANCE + 0.25), HitboxScript.LAYER_WORLD)
        query.exclude = [get_rid()]
        var hit := get_world_3d().direct_space_state.intersect_ray(query)
        if not hit.is_empty():
            reach = clampf(eye.distance_to(hit["position"]) - 0.25, 0.0, LEAN_DISTANCE)
    arm_pivot.position.x = lean * reach
    arm_pivot.rotation.z = -lean * LEAN_ROLL

## World point under the crosshair (same ray as the shot, without spread).
func crosshair_point() -> Vector3:
    var origin := camera.global_position
    var forward := -camera.global_transform.basis.z
    if not first_person_view and not is_scope_active():
        var chest := global_position + Vector3(0, height * (0.25 if prone else 0.75), 0)
        origin += forward * maxf(0.0, (chest - origin).dot(forward))
    var far := origin + forward * 700.0
    var hit := _shot_ray(origin, far)
    return hit["position"] if not hit.is_empty() else far

## Ray against the world and hit volumes. A hit "shell" (survival zombies: one
## capsule per body instead of a physics body per bone) resolves the exact body
## part by math; when the ray passes between arms and legs it continues past it.
func _shot_ray(from: Vector3, to: Vector3, from_inside: bool = false) -> Dictionary:
    var exclude: Array[RID] = [get_rid()]
    var direction := (to - from).normalized()
    for attempt in range(6):
        var query := PhysicsRayQueryParameters3D.create(from, to, HitboxScript.SHOT_MASK)
        query.exclude = exclude
        query.hit_from_inside = from_inside
        var hit := get_world_3d().direct_space_state.intersect_ray(query)
        if hit.is_empty():
            return hit
        var collider: Object = hit["collider"]
        if collider == null or not collider.has_method("resolve_ray"):
            return hit
        var part: Dictionary = collider.call("resolve_ray", from, direction)
        if not part.is_empty():
            hit["position"] = part["position"]
            hit["normal"] = part["normal"]
            return hit
        exclude.append(hit["rid"])
    return {}

## Shot cone radius (tangent of the half-angle) right now; the HUD crosshair
## draws this same value, so the gap always matches where rounds can land.
func current_spread() -> float:
    if has_bow():
        return lerpf(0.018, 0.002, float(bow_controller.get("draw").charge))
    # Accuracy: tighter when aiming, wider when running or airborne.
    var stats: Dictionary = WeaponData.stats(current_weapon)
    var planar_speed := Vector2(velocity.x, velocity.z).length()
    var spread := float(stats["spread"]) * (WeaponData.AIM_SPREAD if aiming else 1.0)
    if not shield_id.is_empty() and current_weapon != "pistol":
        spread *= SHIELD_ONE_HAND_SPREAD
    if prone:
        spread *= WeaponData.CROUCH_SPREAD * 0.6 # deitado e apoiado: o tiro mais firme
    elif crouching:
        spread *= WeaponData.CROUCH_SPREAD
    spread *= 1.0 + clampf(planar_speed / speed, 0.0, 1.6) * 0.6
    if not is_on_floor():
        spread *= 1.8
    return spread

## 0 = hip, 1 = sights fully up (first-person ADS).
func ads_amount() -> float:
    if not first_person_view or viewmodel == null:
        return 0.0
    return float(viewmodel.call("ads_amount"))

## True while aiming through an optic (the HUD dot becomes the red-dot reticle).
func ads_optic() -> bool:
    return first_person_view and viewmodel != null and bool(viewmodel.call("has_optic"))

## Where a shot starts this frame: the aim-ray origin and direction, the
## barrel (third-person muzzle, viewmodel muzzle in first person) and a wall
## between the head and the aim start, if any. Shared by _shoot() and the
## crosshair prediction, so the HUD never disagrees with the real round.
func _aim_setup() -> Dictionary:
    var origin := camera.global_position
    var forward := -camera.global_transform.basis.z
    var muzzle := weapon_model.get_node_or_null("Muzzle") as Marker3D if weapon_model != null else null
    var barrel: Vector3 = muzzle.global_position if muzzle else gun_flash.global_position
    if first_person_view:
        # CS-style: the round leaves the eye/crosshair axis; the tracer starts at
        # the visible viewmodel barrel, and the hidden third-person gun is ignored.
        muzzle = null
        barrel = viewmodel.call("muzzle_position")
    # Leaning (Q/E while aiming) slides the view sideways out of cover; the gun
    # and the head go with it. Without this the round left from the un-leaned
    # barrel, still behind the wall the camera was peeking past.
    var lean_offset := global_basis.x * arm_pivot.position.x
    if muzzle:
        barrel += lean_offset
    # Something solid between the shooter's head and where the shot really starts
    # (a wall you are pressed against): the round stops on it.
    var wall_block := {}
    if not first_person_view and not is_scope_active():
        # Shoulder camera: start the aim ray at the depth of the gun barrel, not
        # at the camera. Hugging cover, the camera (behind and beside the
        # shoulder) would otherwise hit the cover's corner a few cm away and the
        # round would leave the barrel sideways toward that point.
        var chest := global_position + Vector3(0, height * (0.25 if prone else 0.75), 0)
        var depth := (chest - origin).dot(forward)
        if muzzle:
            depth = maxf(depth, (barrel - origin).dot(forward))
        origin += forward * maxf(0.0, depth)
        # Skipping that stretch must not let anyone shoot through a wall: the
        # head has to see the new start point. Over a low cover it does.
        var eye := global_position + Vector3(0, height * (0.25 if prone else 0.9), 0) + lean_offset
        var guard := PhysicsRayQueryParameters3D.create(eye, origin, HitboxScript.LAYER_WORLD)
        guard.exclude = [get_rid()]
        guard.hit_from_inside = true
        wall_block = get_world_3d().direct_space_state.intersect_ray(guard)
    return {"origin": origin, "forward": forward, "barrel": barrel, "use_barrel": muzzle != null, "wall_block": wall_block}

## One round along `direction`: {hit, endpoint}. The camera picks the aim
## point; the round itself leaves the barrel and stops on what is in its way.
func _shot_path(aim: Dictionary, direction: Vector3, shot_range: float) -> Dictionary:
    var origin: Vector3 = aim["origin"]
    var barrel: Vector3 = aim["barrel"]
    var wall_block: Dictionary = aim["wall_block"]
    var target := origin + direction * shot_range
    var hit := _shot_ray(origin, target)
    var endpoint: Vector3 = hit["position"] if not hit.is_empty() else target
    if not wall_block.is_empty():
        return {"hit": wall_block, "endpoint": wall_block["position"]}
    if bool(aim["use_barrel"]):
        # A wall between the barrel and the target still blocks it, but not the
        # lip of the cover right in front of the gun (the first
        # BARREL_CLEARANCE m): the head already sees over it, like in any cover
        # shooter, and the round clears it.
        var barrel_direction := (endpoint - barrel).normalized()
        var barrel_length := barrel.distance_to(endpoint)
        if barrel_length > BARREL_CLEARANCE:
            var barrel_start := barrel + barrel_direction * BARREL_CLEARANCE
            var barrel_hit := _shot_ray(barrel_start, endpoint + barrel_direction * 0.02, true)
            # Retain a camera hit if numerical rounding at its surface misses it.
            if not barrel_hit.is_empty():
                hit = barrel_hit
        if not hit.is_empty():
            endpoint = hit["position"]
    return {"hit": hit, "endpoint": endpoint}

## Crosshair honesty: where the round would really stop if fired now, when
## that is short of what the camera shows at the crosshair (a wall the
## camera sees past, the cover in front of the gun). {} = the shot is clear.
## The HUD turns the crosshair red and marks this point.
var _aim_block_cache := {}
var _aim_block_frame := -1
func predict_shot_block() -> Dictionary:
    var frame := Engine.get_process_frames()
    if frame == _aim_block_frame:
        return _aim_block_cache
    _aim_block_frame = frame
    _aim_block_cache = {}
    if weapon_holstered or first_person_view or is_scope_active() or camera == null or weapon_model == null:
        return _aim_block_cache
    var aim := _aim_setup()
    var range_value := float(WeaponData.stats(current_weapon)["range"])
    var forward: Vector3 = aim["forward"]
    var origin: Vector3 = aim["origin"]
    var path := _shot_path(aim, forward, range_value)
    var endpoint: Vector3 = path["endpoint"]
    # What the camera itself shows under the crosshair: first thing the view
    # ray meets past the barrel depth (the cover corner beside the camera does
    # not count, the round ignores it too).
    var view_hit := _shot_ray(origin, origin + forward * range_value)
    var view_point: Vector3 = view_hit["position"] if not view_hit.is_empty() else origin + forward * range_value
    var eye := camera.global_position
    var shortfall := view_point.distance_to(eye) - endpoint.distance_to(eye)
    if shortfall > AIM_BLOCK_MARGIN:
        _aim_block_cache = {"point": endpoint, "normal": (path["hit"] as Dictionary).get("normal", -forward)}
    return _aim_block_cache

func _shoot() -> void:
    if ammo <= 0:
        _reload()
        return
    var stats: Dictionary = WeaponData.stats(current_weapon)
    ammo -= 1
    magazines[current_weapon] = ammo
    shots += 1
    fire_delay = float(stats["interval"])
    gun_flash.light_energy = 2.8
    gun_flash.visible = true
    gun_kick = float(stats["kick"])
    sound_fx.shot(current_weapon)
    if humanoid_avatar != null and humanoid_avatar.has_method("notify_shot"):
        humanoid_avatar.call("notify_shot")
    var aim := _aim_setup()
    var origin: Vector3 = aim["origin"]
    var forward: Vector3 = aim["forward"]
    last_shot_origin = aim["barrel"]
    var spread := current_spread()
    for pellet in range(int(stats["pellets"])):
        # Uniform disc (not a square) around the crosshair.
        var angle := randf() * TAU
        var radius := sqrt(randf()) * spread
        var direction := (forward + camera.global_transform.basis.x * cos(angle) * radius + camera.global_transform.basis.y * sin(angle) * radius).normalized()
        var path := _shot_path(aim, direction, float(stats["range"]))
        var hit: Dictionary = path["hit"]
        var endpoint: Vector3 = path["endpoint"]
        if pellet == 0:
            var tracer_origin := last_shot_origin
            if is_scope_active():
                var offset := clampf(origin.distance_to(endpoint) * 0.5, camera.near * 2.0, 2.0)
                tracer_origin = origin + forward * offset
            _shot_tracer(tracer_origin, endpoint)
            shot_fired.emit(current_weapon, last_shot_origin, endpoint)
        if not hit.is_empty():
            var target_node: Object = hit["collider"]
            if target_node != null and target_node.has_method("take_hit"):
                # Body-part hitbox: the match controller handles feedback and the server damage.
                target_node.call("take_hit", float(stats["damage"]), endpoint, hit["normal"], current_weapon)
                continue
            if target_node != null and target_node.has_method("take_damage"):
                target_node.call("take_damage", float(stats["damage"]))
            _impact_mark(endpoint)

## Online match start: no weapons, no ammo, nothing in hand.
func start_unarmed() -> void:
    loadout_limited = true
    owned_weapons.clear()
    slot_order.clear()
    melee_slots.clear()
    melee_weapon = ""
    if has_bow():
        bow_controller.call("unequip")
    for weapon_id in reserve_ammo.keys():
        reserve_ammo[weapon_id] = 0
        magazines[weapon_id] = 0
    ammo = 0
    reloading = false
    if not weapon_holstered:
        _toggle_weapon_holster()

## A weapon from a loot crate: adds reserve ammo, and draws it if the hands were empty.
func give_weapon(weapon_id: String, reserve: int) -> void:
    if not WeaponData.DATA.has(weapon_id):
        return
    var first := owned_weapons.is_empty()
    var new_weapon := not owned_weapons.has(weapon_id)
    owned_weapons[weapon_id] = true
    if new_weapon:
        slot_order.append(weapon_id)
    reserve_ammo[weapon_id] = int(reserve_ammo.get(weapon_id, 0)) + reserve
    if new_weapon:
        magazines[weapon_id] = int(WeaponData.stats(weapon_id)["mag"])
    if first:
        _equip_weapon(weapon_id)
        ammo = int(magazines[weapon_id])
        if weapon_holstered and weapon_id != "bow":
            _toggle_weapon_holster()
    elif weapon_id == current_weapon and new_weapon:
        ammo = int(magazines[weapon_id])

## Survival: the weapon left the backpack (dropped, death). Draws another one or holsters.
func remove_weapon(weapon_id: String) -> void:
    if weapon_id == "bow" and has_bow():
        bow_controller.call("unequip")
    if not owned_weapons.has(weapon_id):
        return
    owned_weapons.erase(weapon_id)
    slot_order.erase(weapon_id)
    reserve_ammo[weapon_id] = 0
    magazines[weapon_id] = 0
    if current_weapon != weapon_id:
        return
    var next_gun := ""
    for slot in slot_order:
        if not melee_slots.has(slot):
            next_gun = slot
            break
    if next_gun.is_empty():
        ammo = 0
        reloading = false
        if not weapon_holstered:
            _toggle_weapon_holster()
    else:
        _equip_weapon(next_gun)

## Sobrevivência: arma branca entrou na mochila — ganha o próximo slot livre
## (1, 2, 3... na ordem em que as armas chegaram), sem sacar sozinha.
func give_melee(item_id: String, display_name: String) -> int:
    if not melee_slots.has(item_id):
        melee_slots[item_id] = display_name
        slot_order.append(item_id)
    return slot_order.find(item_id) + 1

## A arma branca saiu da mochila: libera o slot (os seguintes sobem um).
func remove_melee(item_id: String) -> void:
    if not melee_slots.has(item_id):
        return
    melee_slots.erase(item_id)
    slot_order.erase(item_id)
    if melee_weapon == item_id:
        melee_weapon = ""

## Tecla do slot de uma arma branca: guarda a arma de fogo/arco e pega a
## arma branca; apertar de novo a mesma tecla guarda (mãos vazias).
func select_melee(item_id: String) -> void:
    if has_bow():
        bow_controller.call("unequip")
    if melee_weapon == item_id:
        melee_weapon = ""
        return
    if not weapon_holstered:
        _toggle_weapon_holster()
    melee_weapon = item_id

## Nome do que está no slot (arma de fogo ou arma branca).
func slot_label(slot_id: String) -> String:
    if melee_slots.has(slot_id):
        return str(melee_slots[slot_id])
    return str(WeaponData.stats(slot_id)["name"])

## O slot `slot_id` é o que está na mão agora?
func slot_in_hand(slot_id: String) -> bool:
    if melee_slots.has(slot_id):
        return melee_weapon == slot_id
    if slot_id == "bow":
        return has_bow()
    return slot_id == current_weapon and not weapon_holstered and melee_weapon.is_empty()

## Called by the online match when the server reports damage to this player.
func add_hit_shake(strength: float) -> void:
    hit_shake = clampf(hit_shake + strength, 0.0, 1.2)
    # A small aim punch upward, like being struck.
    pitch = clampf(pitch + strength * 0.03, -1.15, 0.95)

func _shot_tracer(from: Vector3, to: Vector3) -> void:
    var delta_pos := to - from
    var length := minf(delta_pos.length(), 45.0)
    if length < 0.1:
        return
    var tracer := MeshInstance3D.new()
    tracer.name = "ShotTracer"
    var cylinder := CylinderMesh.new()
    var radius := 0.011
    if is_scope_active():
        # Keep the scoped trail near one pixel wide even at maximum magnification.
        var viewport_height := maxf(camera.get_viewport().get_visible_rect().size.y,1.0)
        radius = 2.0 * camera.global_position.distance_to(from) * tan(deg_to_rad(camera.fov) * 0.5) / viewport_height
    cylinder.top_radius = radius
    cylinder.bottom_radius = radius
    cylinder.height = length
    cylinder.radial_segments = 5
    tracer.mesh = cylinder
    var glow := StandardMaterial3D.new()
    glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    glow.albedo_color = Color("#ffd08c")
    tracer.material_override = glow
    tracer.position = from + delta_pos.normalized() * length * 0.5
    tracer.quaternion = Quaternion(Vector3.UP, delta_pos.normalized())
    get_tree().current_scene.add_child(tracer)
    var tween := tracer.create_tween()
    tween.tween_property(tracer, "transparency", 1.0, 0.075)
    tween.tween_callback(tracer.queue_free)

func _impact_mark(point: Vector3) -> void:
    var impact := MeshInstance3D.new()
    var sphere := SphereMesh.new()
    sphere.radius = 0.085
    sphere.height = 0.17
    impact.mesh = sphere
    impact.material_override = _material(Color("#eacb91"))
    get_tree().current_scene.add_child(impact)
    impact.global_position = point
    var tween := impact.create_tween()
    tween.tween_property(impact, "scale", Vector3.ZERO, 0.23)
    tween.tween_callback(impact.queue_free)



func _animate_avatar(delta: float, input_amount: float, grounded: bool) -> void:
    if humanoid_avatar != null:
        if humanoid_avatar.has_method("set_aim_pitch"):
            humanoid_avatar.call("set_aim_pitch", pitch)
        if humanoid_avatar.has_method("set_aim_target"):
            # Third-person barrel follows the crosshair (not while sprinting/reloading).
            var aim_ready := not weapon_holstered and not reloading and not sprinting
            humanoid_avatar.call("set_aim_target", crosshair_point(), aim_ready)
        var running := sprinting
        if humanoid_avatar.has_method("set_prone"):
            humanoid_avatar.call("set_prone", prone)
        if humanoid_avatar.has_method("set_swimming"):
            humanoid_avatar.call("set_swimming", swimming)
        if humanoid_avatar.has_method("set_shield"):
            humanoid_avatar.call("set_shield", shield_id, shield_raised)
        humanoid_avatar.call("animate", delta, input_amount, running, crouching, aiming, not grounded, reloading, Input.get_vector("move_left", "move_right", "move_forward", "move_back"), humanoid_avatar.global_basis.inverse() * get_real_velocity())
        return
    if jaime_model != null and jaime_animation != null:
        var moving := input_amount > 0.1 and grounded
        var next_clip := "idle"
        if not grounded:
            next_clip = "jump" if velocity.y > 0.0 else "fall"
        elif reloading:
            next_clip = "reload_walk" if moving else "reload"
        elif crouching:
            next_clip = "crouch_aim_walk" if aiming and moving else ("crouch_aim" if aiming else ("crouch_walk" if moving else "crouch"))
        elif aiming:
            next_clip = "aim_walk" if moving else "aim"
        elif moving:
            next_clip = "run" if sprinting else "walk"
        _play_jaime_animation(next_clip)
        return
    # Compact procedural animation for the prototype mesh; animation resources can replace it later.
    var running := sprinting
    var moving := input_amount > 0.1 and grounded
    var pace := 11.0 if running else (5.5 if crouching else 7.5)
    if moving:
        avatar_anim_time += delta * pace
    var stride := sin(avatar_anim_time) * (0.54 if running else (0.20 if crouching else 0.37)) if moving else 0.0
    var blend := minf(delta * 11.0, 1.0)
    var left_leg := avatar.get_node_or_null("LeftLeg") as Node3D
    var right_leg := avatar.get_node_or_null("RightLeg") as Node3D
    var left_arm := avatar.get_node_or_null("LeftArm") as Node3D
    var right_arm := avatar.get_node_or_null("RightArm") as Node3D
    if left_leg != null:
        left_leg.rotation.x = lerpf(left_leg.rotation.x, stride, blend)
    if right_leg != null:
        right_leg.rotation.x = lerpf(right_leg.rotation.x, -stride, blend)
    if left_arm != null:
        var hold_left := -0.42 if aiming else -0.22
        left_arm.rotation.x = lerpf(left_arm.rotation.x, hold_left - stride * 0.12, blend)
    if right_arm != null:
        var hold_right := -0.45 if aiming else -0.22
        right_arm.rotation.x = lerpf(right_arm.rotation.x, hold_right + stride * 0.12, blend)
    var torso := avatar.get_node_or_null("Torso") as Node3D
    if torso != null:
        torso.rotation.z = lerpf(torso.rotation.z, -0.04 * stride, blend)

func _equip_weapon(weapon_id: String) -> void:
    if weapon_id == "bow":
        magazines[current_weapon] = ammo
        current_weapon = "bow"
        ammo = 0
        bow_controller.call("equip")
        return
    if has_bow():
        bow_controller.call("unequip")
    if current_weapon == weapon_id:
        return
    magazines[current_weapon] = ammo
    current_weapon = weapon_id
    ammo = int(magazines[current_weapon])
    reloading = false
    reload_timer = 0.0
    fire_delay = 0.12
    gun_kick = 0.0
    _rebuild_weapon_model()
    if humanoid_avatar != null:
        humanoid_avatar.configure_weapon(current_weapon, weapon_model.scale.x)

func _rebuild_weapon_model() -> void:
    if current_weapon == "bow":
        return
    _rebuild_viewmodel()
    if humanoid_avatar == null or not humanoid_avatar.has_method("bind_weapon"):
        _rebuild_legacy_weapon_model()
        return
    var imported := WeaponProportions.create_model(current_weapon)
    if imported == null:
        _rebuild_legacy_weapon_model()
    else:
        weapon_model.transform = Transform3D.IDENTITY
        for child in weapon_model.get_children():
            weapon_model.remove_child(child)
            child.queue_free()
        weapon_model.add_child(imported)
    equipped_external_model = imported != null
    if WeaponProportions.apply(weapon_model, current_weapon, imported):
        humanoid_avatar.call("bind_weapon", weapon_model)
        var muzzle := weapon_model.get_node("Muzzle") as Marker3D
        gun_flash.position = gun.to_local(muzzle.global_position)
        muzzle_flare.position = gun_flash.position

## Free distance in front of the eye, so the viewmodel can pull back from walls.
func _first_person_clearance() -> float:
    var from := camera.global_position
    var forward := -camera.global_basis.z
    var query := PhysicsRayQueryParameters3D.create(from, from + forward * 1.2)
    query.exclude = [get_rid()]
    var hit := get_world_3d().direct_space_state.intersect_ray(query)
    return INF if hit.is_empty() else from.distance_to(hit["position"])

func _rebuild_viewmodel() -> void:
    # Built before the camera exists during _make_avatar; _ready calls it again.
    if viewmodel != null and viewmodel.is_inside_tree():
        # Arms dressed like the chosen character (sleeves, skin, gloves).
        viewmodel.call("apply_character", CharacterRegistry.definition(character_id))
        viewmodel.call("build", current_weapon)

func _rebuild_legacy_weapon_model() -> void:
    equipped_external_model = false
    weapon_model.scale = Vector3.ONE
    for child in weapon_model.get_children():
        weapon_model.remove_child(child)
        child.queue_free()
    # Optional imported .glb files live in res://assets/weapons/.
    # If none is supplied, the procedural weapon remains fully playable.
    var external_path := "res://assets/weapons/%s.glb" % current_weapon
    if ResourceLoader.exists(external_path):
        var packed := load(external_path) as PackedScene
        if packed != null:
            var imported := packed.instantiate() as Node3D
            if imported != null:
                imported.name = "ImportedWeapon"
                imported.position = Vector3.ZERO
                imported.rotation_degrees = Vector3(0, 180, 0)
                weapon_model.add_child(imported)
                equipped_external_model = true
    if equipped_external_model:
        var length_override := 0.54
        match current_weapon:
            "smg": length_override = 0.82
            "rifle": length_override = 1.18
            "shotgun": length_override = 1.27
            "sniper": length_override = 1.55
        gun_flash.position.z = -0.58 if current_weapon == "pistol" else -length_override * 0.99
        muzzle_flare.position.z = gun_flash.position.z - 0.035
        return
    if current_weapon in ["rifle", "sniper"]:
        weapon_model.scale = Vector3.ONE * 0.7
    var dark := Color("#22272d")
    var steel := Color("#59616a")
    var wood := Color("#765b43")
    var polymer := Color("#343a35")
    var accent := Color("#ab9360")
    var length := 0.54
    if current_weapon == "pistol":
        _part(weapon_model, "Slide", Vector3(0, 0.075, -0.27), Vector3(0.16, 0.16, 0.50), steel)
        _part(weapon_model, "Grip", Vector3(0, -0.15, -0.08), Vector3(0.13, 0.29, 0.14), dark)
        _part(weapon_model, "TriggerGuard", Vector3(0, -0.13, -0.29), Vector3(0.12, 0.045, 0.18), dark)
        _part(weapon_model, "FrontSight", Vector3(0, 0.19, -0.47), Vector3(0.08, 0.055, 0.06), accent)
        _part(weapon_model, "RearSight", Vector3(0, 0.19, -0.08), Vector3(0.12, 0.055, 0.06), dark)
    else:
        if current_weapon == "smg":
            length = 0.82
        elif current_weapon == "rifle":
            length = 1.18
        elif current_weapon == "shotgun":
            length = 1.27
        else:
            length = 1.55
        _part(weapon_model, "Receiver", Vector3(0, 0, -length * 0.35), Vector3(0.19, 0.23, length * 0.52), steel)
        _part(weapon_model, "Barrel", Vector3(0, 0.03, -length * 0.76), Vector3(0.09, 0.09, length * 0.45), dark)
        _part(weapon_model, "Stock", Vector3(0, -0.035, 0.15), Vector3(0.15, 0.16, 0.38), wood if current_weapon == "shotgun" else dark)
        _part(weapon_model, "Grip", Vector3(0, -0.18, -0.21), Vector3(0.12, 0.29, 0.15), dark)
        _part(weapon_model, "Handguard", Vector3(0, -0.035, -length * 0.56), Vector3(0.22, 0.18, length * 0.30), polymer)
        _part(weapon_model, "Rail", Vector3(0, 0.145, -length * 0.36), Vector3(0.17, 0.045, length * 0.42), dark)
        _part(weapon_model, "TriggerGuard", Vector3(0, -0.145, -0.33), Vector3(0.12, 0.045, 0.17), dark)
        if current_weapon != "shotgun":
            _part(weapon_model, "Magazine", Vector3(0, -0.23, -length * 0.39), Vector3(0.13, 0.38, 0.16), dark)
        if current_weapon == "shotgun":
            _part(weapon_model, "Pump", Vector3(0, -0.065, -0.72), Vector3(0.24, 0.15, 0.31), wood)
            _part(weapon_model, "Tube", Vector3(0, -0.12, -0.90), Vector3(0.08, 0.08, 0.45), steel)
        elif current_weapon == "sniper":
            _part(weapon_model, "Scope", Vector3(0, 0.23, -0.34), Vector3(0.15, 0.15, 0.48), dark)
            _part(weapon_model, "Lens", Vector3(0, 0.23, -0.59), Vector3(0.115, 0.115, 0.018), Color("#345d6a"))
            _part(weapon_model, "BipodLeft", Vector3(-0.12, -0.23, -1.04), Vector3(0.045, 0.32, 0.045), dark)
            _part(weapon_model, "BipodRight", Vector3(0.12, -0.23, -1.04), Vector3(0.045, 0.32, 0.045), dark)
        else:
            _part(weapon_model, "FrontSight", Vector3(0, 0.18, -length * 0.91), Vector3(0.085, 0.10, 0.065), dark)
            if current_weapon == "rifle":
                # M4-style silhouette from the supplied reference: rail, holo and foregrip.
                _part(weapon_model, "BufferTube", Vector3(0, 0.015, 0.12), Vector3(0.08, 0.08, 0.38), dark)
                _part(weapon_model, "StockPad", Vector3(0, -0.045, 0.35), Vector3(0.17, 0.28, 0.055), dark)
                _part(weapon_model, "Foregrip", Vector3(0, -0.21, -0.68), Vector3(0.11, 0.28, 0.13), polymer)
                _part(weapon_model, "HoloBase", Vector3(0, 0.205, -0.34), Vector3(0.20, 0.07, 0.23), dark)
                _part(weapon_model, "HoloLeft", Vector3(-0.085, 0.315, -0.34), Vector3(0.035, 0.19, 0.07), dark)
                _part(weapon_model, "HoloRight", Vector3(0.085, 0.315, -0.34), Vector3(0.035, 0.19, 0.07), dark)
                _part(weapon_model, "HoloTop", Vector3(0, 0.405, -0.34), Vector3(0.20, 0.035, 0.07), dark)
                for rib in range(7):
                    _part(weapon_model, "RailRib", Vector3(0, 0.015, -0.55 - rib * 0.045), Vector3(0.245, 0.20, 0.018), dark)
    var muzzle_z := -0.58 if current_weapon == "pistol" else -length * 0.99
    gun_flash.position.z = muzzle_z * weapon_model.scale.z
    muzzle_flare.position.z = gun_flash.position.z - 0.035

func _reload() -> void:
    if current_weapon == "bow":
        return
    if reloading or channel_left > 0.0:
        return
    if int(reserve_ammo[current_weapon]) <= 0 or ammo >= int(WeaponData.stats(current_weapon)["mag"]):
        return
    reloading = true
    reload_timer = ACTION_TIME # every weapon reloads in 3 s (on-screen clock)
    sound_fx.reload()

## Timed action with the on-screen clock (medkit): `done` runs after `seconds`.
func start_channel(label: String, seconds: float, done: Callable) -> bool:
    if has_bow():
        bow_controller.call("cancel_draw")
    if channel_left > 0.0 or reloading:
        return false
    channel_label = label
    channel_total = seconds
    channel_left = seconds
    _channel_done = done
    Input.action_release("fire")
    return true

func cancel_channel() -> void:
    channel_left = 0.0
    _channel_done = Callable()

## For the HUD clock: {label, fraction 0..1, seconds left}, or {} when idle.
func action_progress() -> Dictionary:
    if reloading:
        return {"label": "RECARREGANDO", "fraction": clampf(1.0 - reload_timer / ACTION_TIME, 0.0, 1.0), "left": maxf(reload_timer, 0.0)}
    if channel_left > 0.0:
        return {"label": channel_label, "fraction": clampf(1.0 - channel_left / channel_total, 0.0, 1.0), "left": channel_left}
    return {}

func status_text() -> String:
    if has_bow():
        return "ARCO RECURVO | Segure o botão esquerdo para mirar; solte para disparar | TENSÃO: %d%%" % roundi(float(bow_controller.get("draw").charge) * 100.0)
    if loadout_limited and owned_weapons.is_empty():
        return "SEM ARMA\nAche uma caixa e aperte E"
    var state :="ARMA GUARDADA (H: SACAR)" if weapon_holstered else ("MIRANDO" if aiming else "LIVRE (H: GUARDAR)" )
    if prone:
        state += " / DEITADO"
    elif crouching:
        state += " / AGACHADO"
    var stats: Dictionary = WeaponData.stats(current_weapon)
    if is_scope_active():
        state = "LUNETA %.0f× | RODA: 4–8×" % scope_zoom
    var definition := CharacterRegistry.definition(character_id)
    var character_name: String = definition.display_name if definition != null else "Jaime Original"
    var notice := "\n" + character_fallback_reason if not character_fallback_reason.is_empty() else ""
    if loadout_limited:
        # Pickup-order slots, e.g. "[1] PISTOLA  2 FUZIL" (current one in brackets).
        var slots: Array[String] = []
        for i in slot_order.size():
            slots.append(("[%d] %s" if slot_in_hand(slot_order[i]) else "%d %s") % [i + 1, slot_label(slot_order[i])])
        notice += "\n" + "  ".join(slots)
    return "PERSONAGEM: %s%s\n" % [character_name, notice] + "ARMA: %s  %s/%s +%s  |  TIROS: %s  |  %s" % [stats["name"], ammo, stats["mag"], reserve_ammo[current_weapon], shots, "RECARREGANDO" if reloading else state]
