# Tactical Gear Implementation Plan

> **For agentic workers:** Execute tasks inline with the existing implementation and verification workflow.

**Goal:** Add usable explosive grenades and instant destructible ice cover to solo and online Gameteste.
**Architecture:** Shared pure rules supply ballistic motion, static map collision, blast occlusion and ice placement. Three.js handles visuals and controls. Existing GameRoom owns online inventories, projectiles, walls and damage.
**Tech Stack:** JavaScript, Three.js r128, Cloudflare Durable Objects, node:test.
**Spec:** docs/superpowers/specs/2026-11-12-tactical-gear-design.md

## Global Constraints
Preserve existing gameplay; 3 grenades/3 ice charges per life, 2.8s fuse, 6m blast radius, 260 wall health, 25s wall lifetime. No external art dependency. Do not publish without authorization.

## Review Focus
- Invalid placement, vertical aim and obstacles must not consume charges or spawn inside players.
- Intact walls stop bullets and explosions; destroyed/expired wall colliders disappear.
- Death/menu cancels prepared throws; already thrown grenades continue.
- Multiplayer cannot forge damage, replenish charges, replay wall damage or discard delayed explosions through hibernation.
- Late join/leave and respawn preserve room world state and five-second death behavior.

## Task 1: Shared rules
- [x] Write failing tests for ballistic fuse/bounces, blast falloff/cover, wall placement and original map colliders.
- [x] Implement public/tactical-rules.js with pure functions and identical browser/Worker behavior.
- [x] Run tests and commit rules.

## Task 2: Three.js equipment
- [x] Write failing tests for charges, wall collisions/destruction/cleanup, dead guards and grenade effects/damage.
- [x] Implement public/tactical-gear.js and wire number 4/left mouse/V, preview, HUD, audio, damage and existing collisions in full3d.js/index.html/combat-bots.js.
- [x] Verify actual game bootstrap and existing camera/weapon behavior.

## Task 3: Multiplayer
- [x] Write failing room tests for server inventories, grenade expiry/damage, ice bullet blocking, hibernation and late-join snapshots.
- [x] Integrate shared rules, persistence and room alarms in src/worker.js; wire client events and snapshots.
- [x] Run focused and full suites; compare known baseline failures; request review, fix blockers and commit.
