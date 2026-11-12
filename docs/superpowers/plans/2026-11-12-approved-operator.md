# Approved operator integration

Goal: replace the current local avatar with the approved 2K skinned character and existing 18-bone motion; preserve the current 3D game's physics, camera, combat, inventory, cover, bots and multiplayer.

1. Convert the approved geometry into a Three r128 SkinnedMesh; share immutable geometry and 2K maps, retain per-avatar materials and skeletons. Export the approved motion as a DOM-free module.
2. Implement the existing OperatorAvatar interface plus explicit aiming, sprinting, vertical velocity, jump preparation and weapon selection. Keep jump height on the controller; animate preparation/launch/flight/landing without a second ballistic root displacement.
3. Replace old pose overrides in PistolController and WeaponLootSystem only for the new rig. Preserve existing weapon models, loot, effects, ADS and fire logic. Match stock and hand positions to the approved right-handed calibration.
4. Add runtime tests against the repository's exact Three build: skeleton binding, finite skinned vertices, both equipment modes, physics ownership, right-side weapon clearance, grips, crouch/cover, bots, inventory and muzzle attachment. Run the approved motion suite too.
5. Update cache versions, review changes, commit atomically through GitHub with a compare-and-swap ref update. Confirm Cloudflare deployment and deployed asset contents.

Authorization: user approved character and explicitly authorized integration/publication. Isolated local snapshot of remote main, no existing checkout or user edits. No API credentials are requested or modified.

Progress: character conversion, inventory/pose integration, ADS regression tests and real jump integration are complete locally. Original 19 motion checks passed before integration. Full Three r128 tests cover both equipment modes and game combat.
Ruling: keep the player collider/ballistic root under PlayerController; the visual root may retain a small negative anticipation offset during damping after launch, but never the preview's positive flight parabola. Jump preparation adds 120 ms before launch.

Final review: important findings addressed with a reduced-tessellation skinned hit surface, conservative animated sphere and no static AABB. New regression tests reproduce missing running-leg hits and enforce a combat vertex budget while retaining visible-body hit attribution.
Destination verification: connected GitHub nickname and owner both jaime66fla-crypto (id 347032492); gameteste repository 1452952379 is public, owned by that same identity, with admin/push permissions. Publication target is the same repo whose main source was fetched, and the user explicitly authorized game integration/publication.
