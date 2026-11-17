extends SceneTree
## Grava o banco de sons sintetizado (scripts/audio/sfx_bank.gd) em
## assets/audio/sfx/*.wav, para o jogo só carregar (sem gerar durante a partida).
## Rode da raiz do repositório depois de mexer em qualquer som:
##   godot --headless --path godot --script res://tools/bake_sfx.gd
##   godot --headless --path godot --import
const Synth = preload("res://scripts/audio/synth.gd")
const SfxBank = preload("res://scripts/audio/sfx_bank.gd")

func _init() -> void:
	Synth.use_baked = false
	var t0 := Time.get_ticks_msec()
	SfxBank.warm_all()
	var dir := ProjectSettings.globalize_path(Synth.BAKED_DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	var count := 0
	for key in Synth._cache:
		var wav := Synth._cache[key] as AudioStreamWAV
		var err := wav.save_to_wav(dir.path_join(str(key) + ".wav"))
		if err != OK:
			push_error("falhou %s: %s" % [key, error_string(err)])
			continue
		count += 1
	print("bake_sfx: %d sons gravados em %s (%d ms)" % [count, Synth.BAKED_DIR, Time.get_ticks_msec() - t0])
	quit()
