# Weapons and floor loot implementation plan

Goal: Implement the accepted first version: pistol, SMG, assault rifle, shotgun; floor loot picked up with E; two slots selected with1/2; replaced weapon drops with its remaining magazine; ammo by category; bot ammo drops. No backpacks, chests, attachments or rarity upgrades.

Architecture: WeaponLootSystem owns weapon definitions, individual slot magazines, category reserves, models, safe spawn points and proximity/line-of-sight checks. The existing PistolController remains the firing/reload backend with a selected weapon definition. The avatar hand mount stays stable; long weapons receive procedural two-hand support. Cover and real muzzle collision remain authoritative.

1. Tests first for inventory capacity, exact magazine/reserve preservation, replacement drops, ammo caps, range/line-of-sight pickup and safe placement.
2. Implement the standalone module and four distinct low-poly models. Use known safe starter pickups plus randomized valid points outside obstacles. Decorative loot never blocks bullets or camera.
3. Integrate E and1/2, fire/reload definitions, held automatic fire for SMG/rifle, shotgun pellet aggregation, compact HUD/touch buttons and bot drops.
4. Test real combat after switching/reloading/picking up, automatic hold/release, shotgun multi-pellet ammo use, cover fire gate, and long-gun hand/muzzle poses. Review before publishing.
5. Publish atomically against the current remote head and verify deployment plus served bytes.

Invariants: changing guns cancels reload without adding ammo; no shared-magazine duplication; a dropped gun has no extra spawn ammo bonus; ammo types stay separate; pickup cannot reach through walls; pause/blur/respawn clears held firing. First-person and cover remain damageable using actual geometry.
