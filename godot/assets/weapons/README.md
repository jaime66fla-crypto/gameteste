# Modelos GLB para o arsenal

O protótipo tenta carregar um modelo externo ao equipar uma arma. Se o arquivo não existir, usa a geometria procedural existente, preservando o combate e a munição.

## Arquivos opcionais
Coloque na pasta `godot/assets/weapons/`:
- `pistol.glb`
- `smg.glb`
- `rifle.glb`
- `shotgun.glb`
- `sniper.glb`

## Direção, escala e ponto de origem
O modelo deve ter a empunhadura próxima da origem local, cano apontando para frente segundo a configuração da cena Godot. O script atualmente aplica rotação de 180 graus no eixo Y aos modelos importados. Ajuste a orientação no Godot se seu GLB usar outro sistema de eixos. A escala não é alterada automaticamente: exporte em metros e verifique tamanho e posição no editor.

**Importante**: o clarão do disparo usa um deslocamento padronizado baseado no tipo de arma, não a ponta exata do GLB. Para modelos novos, o ponto de saída deverá ser refinado.

## Recomendações de desempenho
- Prefira 1 material para acessórios simples, texturas menores para Web e LOD para modelos complexos.
- Use GLB com materiais PBR e texturas embutidas, verificando licenças de uso.
- Não substitua o personagem Jaime ou o projeto inteiro por apenas um modelo de arma.

## Teste de integração
Execute o jogo, alterne entre 1 a 5, mire, atire e recarregue. Remova temporariamente um GLB e confirme que a arma geométrica aparece no lugar.
