extends SceneTree
var failures := 0
var launches := 0
var launch_reserve := -1
var player: Node3D
func check(ok: bool, label: String) -> void:
	print(('ok: ' if ok else 'FAIL: ') + label)
	if not ok: failures += 1
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	player = load('res://scripts/player.gd').new()
	root.add_child(player)
	await physics_frame
	player.set_physics_process(false)
	var bow: Node = player.get('bow_controller')
	bow.set_physics_process(false)
	check(bow != null, 'all player scenes install one shared bow controller')
	player.call('start_unarmed')
	player.set('loadout_limited', true)
	player.call('give_weapon', 'bow', 2)
	check(player.call('has_bow') and player.get('weapon_holstered'), 'first online weapon equips bow without firearm model')
	player.connect('shot_fired', func(w, o, e):
		if w == 'bow':
			launches += 1
			launch_reserve = player.get('reserve_ammo')['bow']
			check((e-o).length() >= 20.0, 'network launch carries ballistic velocity')
	)
	bow.call('_fire', 1.0)
	check(launches == 1 and launch_reserve == 2 and player.get('reserve_ammo')['bow'] == 1, 'launch precedes consumption and consumes one arrow')
	bow.call('_fire', 0.5)
	bow.call('_fire', 1.0)
	check(launches == 2 and player.get('reserve_ammo')['bow'] == 0, 'empty online bow cannot create extra projectiles')
	player.call('give_weapon', 'pistol', 10)
	player.call('_equip_weapon', 'pistol')
	check(not player.call('has_bow'), 'firearm switching cancels bow pose')
	player.call('_equip_weapon', 'bow')
	player.call('remove_weapon', 'bow')
	check(not player.call('has_bow'), 'dropping bow clears held bow')
	player.queue_free()
	await process_frame
	print('Bow all-modes integration failures: ', failures)
	quit(1 if failures else 0)
