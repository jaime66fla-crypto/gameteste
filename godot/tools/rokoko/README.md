# Rokoko to SWAT locomotion

Rebuild from the project directory using Godot 4.7.2 after native FBX imports finish:

```powershell
& $godot --headless --path . --script tools/rokoko/inspect.gd
& $godot --headless --path . --script tools/rokoko/build_locomotion.gd
& $godot --headless --path . --script tests/rokoko_locomotion.gd
```

`inspection.json` records all 16 original rigs, global rest transforms, imported clip names, lengths and position track endpoints. `report.json` records the verified 52-bone map for every source, selected aliases, cycle crops, removed heading, source displacement and loop measurements. Imported rigs are already in Godot meters. Retargeting transfers normalized global rotational motion using the existing SWAT rest-frame algorithm, preserving all target rest translations and scales. Only pelvis vertical compensation is animated; XZ displacement is removed. No source assets or import skeleton rest poses are modified.

The 76-bone Rokoko family (01–07) maps its four-segment spine to SWAT Spine/Spine1/Spine2 using Spine1/Spine2/Spine4; its extra metacarpals, tips and root nodes are omitted. The 54-bone Mixamo family (08–16) maps the `mixamorig_` names to the target's `mixamorig` names. The HumanSoldier directionals use the existing `B-*` mapping and torso distribution. Missing target bones abort the bake.

Runtime forward walk is a matched active cycle from `02-walkforward.fbx`, 7.166667–8.3 seconds. Forward run is from `05-running-treadmill.fbx`, 6.746666–7.68 seconds. The cycle search rejects stationary intervals using leg angular excursion before scoring endpoint similarity. The other fourteen directions use their actual HumanSoldier Walk01/Run01 directional recordings. Available happy, cool, pacing, wind and injured takes retain their original identities in the inventory and are not presented as separate runtime gaits. There is no independently identified sprint recording: sprint must explicitly speed up run. Treadmill/in-place source displacement cannot establish a meaningful nominal travel speed.

Clips contain 52 quaternion rotation tracks and one hips position track, sampled at 60 Hz. The final 100 ms blends to the first pose using smoothstep, closing rotation and position endpoints exactly. This removes a positional wrap discontinuity; it does not claim matching endpoint angular velocities. Pelvis height compensates the lower toe each sampled frame. Foot locking and controller velocity synchronization belong to the runtime integration.

All walk outputs use a 0.833333333-second period and all runs use a 0.566666667-second period. After the source cycle is closed, the builder searches the retargeted left foot at 120 Hz for maximum reach along the alias's travel direction in target skeleton space (`Vector3(-direction.x, 0, -direction.y)`). That event becomes phase zero. The complete closed cycle is then resampled by normalized phase at the common gait period. Report fields preserve the original source cycle period, duration ratio, source-time phase offset, normalized phase offset and foot projection range. This is a geometric phase convention, not a detected foot-contact event; foot planting remains the runtime's responsibility.

`scripts/characters/locomotion_library.gd` exposes `load_library()` and `build_blend_space()`. Add the returned library as the AnimationPlayer's default library (empty name). Clip paths expect `Soldier/Node/Skeleton3D`. The blend space contains idle at zero, eight walks at radius 0.5 and eight runs at radius 1; X means right and Y means backward. Normalize diagonals before setting blend position. The blend space synchronizes gait times; its clips are full-body so the runtime may apply its armed upper-body filter separately.

Validation checks all source maps, all 17 runtime aliases, quaternion finiteness/normalization, wrap seams, absence of scale and child translation tracks, constant hips XZ, 17-point blend construction and actual target global transforms at 17 subframes per clip. Visual skin/contact quality still requires the runtime scene review. Source redistribution remains subject to the separately documented source licenses.
