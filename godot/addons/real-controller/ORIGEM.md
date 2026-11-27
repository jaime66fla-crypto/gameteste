# real-controller — origem e licença

- Veio de `real-controller-main.zip` (sem LICENSE nem README no zip). Fica fora
  do export (`addons/*` no `exclude_filter`); o jogo usa só os clipes
  retargetados em `assets/personagens/downloaded/movements/`:
  `sprint_unarmed` (sprint_forward), `jump_unarmed_start` (jump_begin),
  `fall_unarmed` (fall) e `land_unarmed` (jump_land), gerados por
  `tools/characters/build_unarmed_locomotion.gd`.
- As animações são do rig **HumanM de Kevin Iglesias** (ossos `B-*`, textura
  `HumanAnimations_ColorPalette`), o mesmo autor do "Human Soldier Animations
  2.0 FREE" que o jogo já usa (`assets/personagens/jaime/animacoes/`, PDF:
  Standard Asset Store EULA — uso comercial sim, revenda não, crédito não
  obrigatório). Sprint/pulo/queda/pouso não estão na lista desse pacote:
  provavelmente "Human Basic Motions FREE" do mesmo autor.
- **A confirmar antes de publicar:** a licença do pacote de onde vieram o
  sprint e o pulo (o site keviniglesias.com não mostra o texto sem script;
  contato: support@keviniglesias.com).
