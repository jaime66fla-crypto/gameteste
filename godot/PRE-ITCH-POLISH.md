# Campo de Fogo - pré-lançamento (branch de polimento)

Versão experimental baseada na branch `godot-migracao`. Não substitui o ZIP mais recente que esteja fora do GitHub.

## O que mudou
- `scripts/world_polish.gd`: iluminação quente, neblina, estradas, construções, árvores e pedras determinísticas.
- `scripts/sound_fx.gd`: áudio mono 22,05 kHz gerado em memória para pistola, recarga e passos, sem arquivos ou licenças externos.
- `scripts/player.gd`: visual da pistola, clarão, traçante, marcas de impacto, recuo e sons; sem alterar velocidade, salto ou mira.
- `scripts/main.gd`: carrega o novo cenário modular.

## Teste antes de exportar
1. Faça backup do seu projeto atual.
2. No Godot 4, abra a pasta `godot` desta branch (com `project.godot`).
3. Confirme que a cena inicia sem erros no painel de depuração.
4. Ande, corra, agache, mire e atire; verifique passos, recuo, flashes e recarga.
5. Observe o cruzamento das ruas e superfícies com câmera baixa: linhas piscando ou tremendo indicam z-fighting.
6. Valide colisão dos edifícios, árvores, desempenho e áudio no navegador.
7. Só depois exporte para Web. Não publique sobre a versão atual antes da revisão visual.

## Limitações conhecidas
- Assets sonoros gerados por síntese simples; não representam mixagem final profissional.
- Código integrado no GitHub, mas execução no editor Godot e exportação Web ainda não validadas neste ambiente.
- O projeto Godot nesta branch é um protótipo menor; o ZIP local pode conter mecânicas mais recentes.
