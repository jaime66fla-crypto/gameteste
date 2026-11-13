# Jaime primary avatar

User-approved goal: integrate the supplied avatar_editor.html as the primary game character, named Jaime, and apply textures.

Approach: bake the supplied articulated mesh and facial details into the existing 18-bone skinned runtime. Keep the game animation/controller, weapon IK, damage, network and jetpack interfaces. Disable the previous operator armor overlay for Jaime so it cannot cover the new face. Share deterministic camo, fabric, skin, leather and hair surface maps across instances.

- [x] Add identity, source provenance, texture and primary-lobby regression tests and observe failure.
- [x] Adapt source geometry and material slots to the existing runtime and make Jaime default for local player, lobby and remote players.
- [x] Verify the entire combat/movement/pose suite (55 passing tests); independent review passed after mesh-based hand-contact correction.
- [ ] Publish with the validation gate and verify deployment/served asset versions.
