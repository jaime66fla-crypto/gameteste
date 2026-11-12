# Damage feedback and delayed respawn

Baseline: ddc64062747fea10560d4a0e4f7a7903b222b454. User requests noticeable incoming damage, a fallen body at death rather than immediate teleport, and respawn after five seconds.

Implemented visible hit vignette and damage amount, persistent life bar with critical-health pulse, short impact audio and camera reaction. PlayerLife provides one death transition, local countdown and server-authorized online resurrection. Both bots and online damage hold health at zero during death. Input, movement, firing, pickups and cover are blocked while dead; camera shows the fallen character. The existing skeleton supplies a damped collapse pose without changing mesh, shaders or textures.

Online deaths persist deadUntil in socket attachments and schedule a Durable Object alarm. Dead state cannot move or shoot, corpses cannot take further damage, and only an expired alarm emits respawn3d. The deadline survives hibernation. Local and remote corpse placement respects supported roofs/platforms rather than sinking to terrain. Solo mode uses elapsed frame time for its five-second delay.

Validation: 21 tests pass with game runtime assertions for visible damage/HP changes, dead ADS visibility, blocked firing, preserved corpse position and rooftop support. Pure lifecycle test covers exactly five seconds and online wait-for-server. Real server class tests cover death, dead movement rejection, hibernation restoration, deadline and single respawn. Independent review found roof support and mobile input issues; both fixed with regression coverage.

Browser graphical playtest remains limited by hosted WebGL support; live deployment verification separately exercises real WebSocket death/respawn timing.
