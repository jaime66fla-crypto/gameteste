# Fishing, fuel and action audio implementation plan

Goal: Liters/km vehicle consumption, craftable rod with right-click bite timing, positional animal and gathering sounds.
Approved design: user approved these three changes and specified right mouse to hook.
Architecture: authoritative server owns fuel and fishing rewards; client displays liters, fishing pose/bobber and nearby sounds. Keep existing save version, no reset. Windows only; do not publish until verified.

1. Fuel: retain save units as liters (100L capacity), use configured L/km rates, update all percent labels including can. Test stationary, cumulative distance, empty tank and refuel cap.
2. Fishing: craft rod from stick/fiber/rope, raw/cooked fish and cooking recipe. Server validates rod, nearby water, alive/on foot, cast timing and one reward per cast, weight capacity, movement cancellation. Client starts fishing with E at water when rod in inventory, indicates bite, right click hooks, Escape/movement cancels; visible held rod and fishing pose synchronized. Tests invalid/repeated/early/late catches and valid reward.
3. Audio: positional boar/deer/wolf ambient/pain calls and repeated timed tree/stone impacts only while collecting, cancel promptly; avoid excessive concurrent voices. Use existing or procedural original sounds.
4. Run focused server tests and Godot parse/runtime checks; review diff; apply verified task files to main repo without unrelated edits.

Validation: server fuel/fishing + survival/trunk35 passed; consistency/hydrology12 passed; Godot nature audio20 passed; full survival fishing session passed.
Review corrections: preserve bow equipment, Shift+E freshwater drinking with rod, bounded350ms server network grace; final checks pending.
