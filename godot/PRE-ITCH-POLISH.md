# Campo de Fogo - pré-lançamento (branch de polimento)

Versão experimental baseada na branch `godot-migracao`. Não substitui o ZIP mais recente que esteja fora do GitHub.

## O que mudou
- `scripts/world_polish.gd`: iluminação quente, neblina, estradas, construções, árvores e pedras determinísticas.
- `scripts/sound_fx.gd`: áudio mono 22,05 kHz gerado em memória para pistola, recarga e passos, sem arquivos ou licenças externos.
- `scripts/player.gd`: arsenal com 5 armas, munição por arma, recarga, disparo hitscan, dispersão, clarão, traçante e impacto; sem alterar a movimentação.
- `scripts/weapon_data.gd`: tabela de equilíbrio de dano, cadência, alcance, dispersão e tamanho de carregador.
- `scripts/ambient_audio.gd`: vento suave em loop, sintetizado em memória.
- `scripts/main.gd`: carrega o novo cenário modular.

## Teste antes de exportar
1. Faça backup do seu projeto atual.
2. No Godot 4, abra a pasta `godot` desta branch (com `project.godot`).
3. Confirme que a cena inicia sem erros no painel de depuração.
4. Ande, corra, agache, mire e atire; verifique passos, recuo, flashes e recarga.
5. Aperte 1 a 5 para alternar pistola / SMG / fuzil / escopeta / sniper. Verifique munição separada, recarga, dispersão e recuo.
6. Confirme que áudio ambiente permanece baixo e contínuo, e que os efeitos de disparo não estouram o volume.
7. Observe o cruzamento das ruas e superfícies com câmera baixa: linhas piscando ou tremendo indicam z-fighting.
8. Valide colisão dos edifícios, árvores, desempenho e áudio no navegador.
9. Só depois exporte para Web. Não publique sobre a versão atual antes da revisão visual.

## Limitações conhecidas
- Sons de tiro e ambiente são sintetizados; não representam mixagem final profissional.
- Modelos das armas ainda são geométricos/procedurais, não modelos GLB finais.
- Dano é aplicado somente a objetos que implementem `take_damage(amount)`; ainda não foram integrados alvos inteligentes nessa branch.
- Código integrado no GitHub, mas execução no editor Godot e exportação Web ainda não validadas neste ambiente.
- O projeto Godot nesta branch é um protótipo menor; o ZIP local pode conter mecânicas mais recentes.

## Teste automatizado de inicialização
Após instalar Godot 4, abra um terminal na raiz do repositório e execute:

```sh
godot --headless --path godot --script res://tests/polish_smoke.gd
```

O teste inicializa a cena, verifica o avatar, os módulos de cenário e som, alterna entre cinco armas, verifica os carregadores e testa a recarga sem munição reserva. Um retorno diferente de zero significa falha. **Ainda não foi executado aqui**, pois a engine Godot não está instalada neste ambiente.

## Atualização de cenário
- Barreiras de concreto com colisão, caixas industriais e elementos para orientar deslocamento.
- Essa decoração foi criada apenas na branch experimental. Avaliar se sobrepõe construções e caminhos antes do merge.
