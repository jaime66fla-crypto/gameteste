# Jaime integrado (branch experimental)

O script `scripts/player.gd` agora tenta carregar `scenes/jaime personagem.tscn`; caso não exista, tenta `assets/jaime/jaime.glb`. Aplica correção de orientação ao visual, oculta partes geométricas provisórias e a arma embutida `Weapon_pistol`, e usa o `AnimationPlayer` quando disponível.

**Arquivo binário ainda não publicado:** o `assets/jaime/jaime.glb` (aprox. 18 MB) e suas texturas precisam ser copiados do ZIP experimental fornecido anteriormente para `godot/assets/jaime/` antes de executar. Sem isso aparece o personagem geométrico de fallback.

Teste no Godot: F5, WASD, Shift, Ctrl, botão direito, esquerdo, R, teclas 1–5. Verificar câmera, frente/costas, deslocamento, clips de animação, sincronização da arma e eventuais duplicações.

Não foi feito teste de execução em Godot nesta sessão. Não aplicar merge na main até validar.
