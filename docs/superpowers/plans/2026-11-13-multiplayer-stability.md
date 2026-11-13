# Multiplayer stability implementation plan

Goal: apply the fixes approved after the game analysis: jetpack and prone replication, posture-aware hit validation, reproducible regression tests and deployment gated by validation.

Architecture: preserve the existing Three.js r128 game and Cloudflare room protocol. Extend state3d with bounded posture/terrain values and jetpack flags. Validate reported hits against a posture-oriented body envelope on the server; retain shot deduplication and obstacle checks. No broad game refactor.

- [x] Add failing server and real-avatar regression tests for posture, equipment, late joins, hibernation and hit rejection above a prone body.
- [x] Fix client serialization, server sanitization and remote animation. Keep crawling speed and equipment visuals consistent.
- [x] Update server hit geometry for standing, crouched, prone, rotated and airborne targets.
- [x] Restore runnable existing test fixtures and use the vendored Three runtime as the default test dependency.
- [x] Gate deployment on syntax and the full suite; bump script cache versions.
- [ ] Publish after code review and verify GitHub deployment and served versions. Live WebGL was unavailable in the analysis browser; validate server protocol and served assets independently.

Validation before publication: `npm run check` passed for 27 files; `npm test` passed all 53 reported tests with zero failures/skips. Existing fixtures were updated for the approved MK-II rig, animation timing, battle admission, current input events, weapon statistics and map expansion.

Review corrections: validate real skinned head impacts during prone/crouch transitions, and attach local/remote jetpacks to the chest bone.
