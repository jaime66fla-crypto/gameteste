# Proveniência dos assets Polyy e Rokoko

Verificação em 15/11/2026. Este registro documenta os arquivos locais usados na integração; não altera as licenças dos autores nem afirma que todos os clipes extraídos estão ativos no jogo.

## Arquivos de origem

| Arquivo em `C:/Users/jaime/Downloads/` | Tamanho em bytes | SHA-256 |
| --- | ---: | --- |
| `3D_low_poly_guns_pack.zip` | 91304233 | `8BCFFA1EE5A1C9C75C310FAFB486EA8F8A92E1510A0D5D6EECC8BCE42F56A825` |
| `WALK-RUN-CYCLES-MOCAP.zip` | 12218874 | `25FAFD47948E3E8D7A413B471ED3B603CE77AE3670A2BB276A60F53ADB718F9D` |

Os hashes identificam as cópias locais inspecionadas. Não foram comparados a hashes publicados pelos fornecedores, nem foi baixada outra cópia para comparação.

Foi comparado o SHA-256 de cada um dos cinco GLBs e dos 16 FBXs extraídos com sua entrada original no respectivo ZIP: todos coincidem. Transformações de apresentação/importação pertencem ao projeto; os arquivos-fonte verificados permanecem idênticos aos arquivos fornecidos.

## Polyy: armas

Autor declarado no pacote: Polyy, [polyy.ai](https://polyy.ai). O `3D_low_poly_guns_pack/LICENSE.txt` original declara CC0 1.0 e permite copiar, modificar, distribuir e usar comercialmente sem pedir permissão. Atribuição não é obrigatória, mas é apreciada. O pedido de não revender o pacote inalterado como pacote próprio é explicitamente apresentado pelo autor como pedido, sem condição legal adicional. O arquivo original de licença foi preservado em [`assets/weapons/polyy/LICENSE.txt`](../assets/weapons/polyy/LICENSE.txt); o README original está em [`assets/weapons/polyy/README.txt`](../assets/weapons/polyy/README.txt). A licença remete ao [texto legal CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/legalcode).

Seleção extraída de `3D_low_poly_guns_pack/models/` para `assets/weapons/polyy/models/`:

| Uso visual pretendido | Arquivo original |
| --- | --- |
| Pistola | `compact_polymer_pistol.glb` |
| Rifle/carabino | `modern_tactical_carbine.glb` |
| Rifle de precisão | `bolt_action_sniper_rifle.glb` |
| Escopeta | `pump_action_shotgun.glb` |
| Submetralhadora | `compact_submachine_gun.glb` |

Segundo o README do autor, o ZIP contém 25 GLBs gerados com polyy.ai, com materiais/texturas PBR. Esta é a versão de malhas completas, aproximadamente 50 mil triângulos por modelo; não é o ZIP de LOD reduzido. A orientação declarada é cano em −X, modelos centrados na origem e comprimento aproximado de uma unidade. Esses dados orientam ajustes de transformação, mas não substituem a medição e a verificação visual no jogo. PNGs externos e arquivos `.import` gerados pelo Godot são derivados da importação dos GLBs, não downloads adicionais.

## Rokoko: caminhada e corrida

Fonte oficial encontrada: [Rokoko mocap: 16 free walk and run cycle animations](https://www.rokoko.com/resources/rokoko-mocap-16-free-walk-and-run-cycle-animations), também listada no [diretório oficial de recursos gratuitos](https://www.rokoko.com/free-resources). A página oficial identifica capturas de Sam Lazarus com Smartsuit Pro II e Smartgloves e anuncia FBX, esqueleto Mixamo pronto para retargeting e 30 FPS.

O HTML da página contém o link de download oficial [`https://media.rokoko.com/WALK-RUN-CYCLES-MOCAP.zip`](https://media.rokoko.com/WALK-RUN-CYCLES-MOCAP.zip). O nome coincide exatamente com o ZIP local e a quantidade e tema dos 16 FBXs são compatíveis com a descrição. Isso sustenta a associação de proveniência; não comprova identidade binária com o servidor.

A página específica permite usar as animações em projetos de animação, VFX, jogos e arte 3D, inclusive comerciais. Essa permissão foi verificada no HTML original: o extrator de texto principal omitiu a seção central. O ZIP local contém os 16 FBXs e metadados Apple em `__MACOSX`; não contém arquivo de licença nem README. **Não há evidência de CC0 para este pacote Rokoko.** Não foi encontrada nessa página uma licença separada que trate explicitamente de redistribuição dos FBXs crus como pacote de assets ou de obrigação de atribuição; tais permissões não são presumidas a partir do uso comercial em projetos. Crédito de proveniência sugerido: “Locomoção: Rokoko / Sam Lazarus — pacote gratuito de 16 ciclos de caminhada e corrida”.

Arquivos extraídos de `WALK-RUN-CYCLES-MOCAP/` para `assets/personagens/jaime/animacoes/rokoko/` (os metadados `__MACOSX` foram excluídos):

1. `01walkforward_walkspline.fbx`
2. `02-walkforward.fbx`
3. `03-walkspline.fbx`
4. `04-running-out-of-frame.fbx`
5. `05-running-treadmill.fbx`
6. `06-runninginjured-treadmill.fbx`
7. `07-runninginjured.fbx`
8. `08-Loop_HappyWalk_MIXAMO_769_segment.fbx`
9. `09-SlowWalkForward_MIXAMO_769.fbx`
10. `10-WalkCycle_01_MIXAMO_769.fbx`
11. `11-WalkCycle_Cool_MIXAMO_WHS_segment.fbx`
12. `12-WalkCycle_Pacing_MIXAMO_769.fbx`
13. `13-WalkingIntoWind01_MIXAMO_769.fbx`
14. `14-WalkingIntoWind02_MIXAMO_769.fbx`
15. `15-WalkingIntoWind03_MIXAMO_769.fbx`
16. `16-WalkingIntoWind04_MIXAMO_769.fbx`

Os nomes com “Mixamo” descrevem os arquivos/esqueleto fornecidos e não estabelecem que sejam downloads da biblioteca Adobe Mixamo. A condição de loop, deslocamento da raiz, escala, qualidade de retargeting, alinhamento dos pés e adequação da parte superior do corpo ao combate precisam de validação técnica e visual. “Treadmill”, “injured” e “walking into wind” indicam variantes diferentes; não são equivalentes intercambiáveis para a locomoção normal. Este registro não certifica o resultado do retargeting nem uma publicação ou distribuição do projeto.
