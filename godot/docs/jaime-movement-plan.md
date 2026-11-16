# Jaime movement corrections

Recovery: `43092bf6001a4bb43e7ca7c7b02127f53c9bde77`, branch `recovery/jaime-movement-20261114`.
The existing index, active branch and pending merge must remain untouched.

Implement the already approved corrections in the existing procedural controller:
1. Add behavioral regressions for capsule base, low ceilings, acceleration, gait and uneven support; run them before production edits.
2. Resize the capsule about its fixed base. Query standing clearance, excluding the player's RID, before expanding. Keep crouch state, camera and pose while blocked.
3. Retain two-bone leg IK; sample real support under both feet, align soles to the support normal, and limit pelvis adjustment to reachable terrain. Align decorative ground surfaces with physical support.
4. Use actual planar speed with acceleration/braking, and an explicit sprint state with a smooth gait blend. Preserve camera, aiming, weapon and input behavior.
5. Run all GDScript tests, MCP error checking and Godot CLI load checks. Review the final diff against the recovery snapshot. Do not commit implementation, resolve the pending merge, push or publish.

Implementation choices: work in the current project so the configured MCP continues to address it; use an explicit file list for recovery; keep engine defaults for slopes/snap unless tests demonstrate a required change. Native execution, no separate worktree.

## Verification results

- New regressions failed before implementation for capsule resizing/headroom, acceleration/braking, unintended fast gait and feet ignoring raised ground. They pass after implementation.
- Full suite: 13/14 pass. `menu_flow.gd` fails because the preexisting `application/run/main_scene` selects the match instead of the menu. Reproduced unchanged failure using an isolated archive of the recovery commit. Menu and project configuration were preserved.
- Added slope checks: soles align to the support normal and remain above the surface.
- Godot CLI 4.7.2: main scene runs for 120 frames and exits 0. MCP headless editor load exits 0, with no reported script errors. Raw editor stderr includes Unicode/NUL warnings.
- Some runtime tests emit ObjectDB leak warnings; the baseline snapshot also emits two leaked-object warnings when loading/exiting the main scene. No unrelated cleanup was attempted.
- Read-only independent review: no Critical or Important findings in the three changed production scripts.
- Player script comparison: 18 existing functions unchanged; only initialization of collision references, movement/crouch physics and locomotion animation selection changed, with two crouch helper functions added. Weapon, camera, inventory, aim, firing, reload and input code preserved.
- Implementation remains uncommitted. No merge, branch switch or push performed.
