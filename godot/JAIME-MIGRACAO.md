# Migração do Jaime original para Godot

## Origem confirmada

- Avatar atual: `public/operator-avatar.js`, gerado proceduralmente com Three.js.
- Rig do jogo web: `public/operator-motion.js`, 18 ossos.
- Identidade e textura: `public/jaime-wardrobe.js` e materiais no avatar.
- O FBX em `public/assets/models/erika-archer.fbx` é outro personagem e **não deve substituir Jaime**.
- Plano original: `docs/superpowers/plans/2026-11-13-jaime-avatar.md`.

## Próximo trabalho

1. Exportar o Jaime gerado pelo código web para GLB/GLTF com armature e pesos preservados (ou refazer rig com equivalência de ossos).
2. Validar orientação (Godot -Z para frente), escala (metros), UV e materiais PBR, transparência de cabelo e geometria facial.
3. Importar o GLB em `godot/assets/jaime/` e instanciar uma cena de personagem no Godot.
4. Integrar locomocao/aim com AnimationTree e rig; rig IK de duas mãos na arma.
5. Testar no editor Godot: idle, walk, run, crouch, aim, fire, jump e colisões.

## Limitações

A cena Godot atual ainda usa um boneco geométrico provisório. O avatar procedural em JavaScript não pode ser carregado diretamente como uma cena 3D do Godot. Não afirmar migração concluída até existir um GLB validado e testado no editor.
