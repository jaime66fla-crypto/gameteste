# Grenades and instant ice cover

User request: create grenades and research Free Fire's instant Gloo Wall protection for Gameteste.

Reference: Garena's official Gloo Makers blog (https://ff.garena.com/en/article/1144/, May 25 2023) describes emergency cover in close combat and exposed terrain. Gameteste will use original procedural ice geometry and its own balance values.

Implementation choices: Key 4 equips a grenade; holding the left mouse button shows a throwing trajectory, releasing throws an explosive grenade. V immediately deploys a wall 3 metres ahead, perpendicular to camera heading; on-screen controls mirror these actions. Each life starts with 3 grenades and 3 wall charges. Grenades bounce, explode after 2.8 seconds, damage within 6 metres with distance falloff and line-of-sight protection, including self damage. Ice walls have 260 health, last 25 seconds, block movement/bullets/blasts, work with existing cover and take extra grenade damage. Invalid placement does not consume a charge. HUD shows quantities and actions.

Approach: shared deterministic JavaScript rules, procedural Three.js presentation, authoritative multiplayer simulation in the existing room Durable Object. This avoids a local-only illusion in online matches. Client-only damage was rejected because peers could disagree. Third-party character/assets and a new physics engine are unnecessary.

Preserve the current operator, controls, weapon loot, public/private rooms, five-second death lifecycle, and existing audience. Server validates charges, cooldowns, directions and wall placement; room alarms and durable snapshots preserve pending grenades/walls across hibernation. Late joiners receive world snapshots. Grenade damage never passes through static cover or intact ice. Publication remains a separately authorized action.
