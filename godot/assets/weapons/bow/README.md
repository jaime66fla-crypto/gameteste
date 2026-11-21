# Arco e flecha — treino offline

Modelo original criado no Blender, em metros: arco recurvo de aproximadamente
1,25 m, flecha de 0,85 m, para o avatar de 1,80 m. Empunhadura na origem,
vertical +Y no Godot e flecha apontando +Z. A corda fica atrás da empunhadura
(-Z), do lado do arqueiro. O corpo do arco foi corrigido após a conferência
visual do usuário.

Fonte editável: `source/recurve_bow.blend` (coleções separadas para arco e flecha).
O diretório source é ignorado pelo importador Godot para evitar dependência
do importador Blender; o jogo usa `recurve_bow.glb` e `arrow.glb`.
Para reconstruir, executar no Blender `tools/weapons/build_bow.py`.

No treino offline, o suporte do arco fica ao lado direito da mesa de ferramentas,
na posição (44.4, 0, 29.4). E pega/devolve; H guarda; teclas 1–5 sacam arma de
fogo. Segurar o botão esquerdo mira e puxa; soltar dispara uma flecha. A puxada
completa leva 0,9 s; um toque menor que 0,12 s cancela. Flechas ilimitadas no
treino, gravidade, velocidade de 20–48 m/s e dano base de 55 no boneco.
Esc, menus, perda de foco, escalada e troca de arma cancelam sem disparar.

Os novos controles são instalados somente no treino offline. O arco ainda não
é um item da Sobrevivência nem do multiplayer. Nenhuma nova publicação foi feita.

Verificação: `--script res://tests/bow.gd`, cena `res://tests/bow_training.tscn`.
Visual: `res://scenes/previews/bow_preview.tscn`; Espaço alterna puxada/relaxada.
