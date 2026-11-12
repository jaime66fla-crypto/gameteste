# Multiplayer menu connection

Baseline: main 7c9d1fd35d9885db16fb750625a0e8c3ffc1f392. User requested improving the room menu, asked to test first, and authorized proceeding after confirmation that the original buttons were placeholders.

The menu now connects to the existing same-origin /ws Durable Object backend. Admission requires welcome3d, with timeout, cancellation, socket-generation checks and disconnect cleanup. Create rejects occupied codes; join rejects empty rooms; capacity is eight connections. Codes are FLR-XXXXX and rooms last while connected players remain.

Remote players use the current approved 18-bone avatar with pose/weapon synchronization and exponential position/heading interpolation. Local training bots are suspended in online rooms. Movement sends at 10 Hz. Shots and confirmed damage/respawn use existing server messages; first-visible-surface raycasts preserve local cover occlusion. Current five weapon definitions and forest map bounds replace outdated server values.

Menu labels, keyboard operation, responsive card, visible connection status, room code/player list and exit action are implemented. M exits an online room. Input letters no longer trigger gameplay while entering names/codes.

Verification: complete node --test tests/*.test.cjs suite passes 18 tests, including full game runtime assertions for admission, remote skinned hits, walls, health, respawn and disconnect; real server logic checks create/join, state, current weapons, full SMG magazine and duplicate hit protection. Reviewer findings addressed: 2 KiB hibernation attachments now retain only latest ordered shot; shotgun hit feedback deduplicated per blast. Full short-lived shot history remains in active memory.

Scope: positional simulation and visible-hit selection are client driven; this is not a server-authoritative competitive anti-cheat implementation. Floor loot remains per-player. The hosted browser previously lacked WebGL, so rendered gameplay validation must be reported separately from transport/server validation.
