# Campo de Fogo — reconstrução

Branch exclusiva da reconstrução, separada de `main` e `feature/godot-pre-itch-polish`.

## Fluxo combinado

1. Alterações de código são registradas no GitHub nesta branch.
2. No GitHub Desktop, selecione `feature/campo-de-fogo-rebuild`. Antes de alternar branches, proteja alterações locais (commit ou stash e backup).
3. Clique em **Fetch origin** para verificar as atualizações.
4. Se aparecer **Pull origin**, clique nele para aplicar os commits na pasta local. Fetch sozinho **não** atualiza os arquivos de trabalho.
5. Abra no Godot o `project.godot` da pasta conectada ao GitHub e execute F5. Se já estiver aberto, aguarde a atualização de recursos ou reabra o editor.
6. Envie captura de tela e erros do painel Saída/Depurador para a próxima correção.

## Arquivos grandes

O Jaime original usa `assets/jaime/jaime.glb` e texturas PNG, que podem não estar presentes no repositório remoto. Sem esses arquivos o personagem não carrega. Os arquivos binários não são enviados automaticamente pela integração de edição de scripts. É necessário adicioná-los e versioná-los com GitHub Desktop (Git LFS se necessário), ou manter uma cópia local até finalizarmos o fluxo.

## Estado

Esta branch foi criada a partir da versão experimental anterior como ponto de trabalho seguro. **Ainda não é a reconstrução Etapa 1 publicada no Git**, e a nova base em ZIP permanece separada até que seu conteúdo seja integrado e validado. Não faça merge na `main` por enquanto.
