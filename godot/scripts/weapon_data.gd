extends RefCounted
## Weapon balance table. IDs map to keyboard slots 1-4.
const ORDER := ["pistol", "smg", "rifle", "shotgun", "sniper"]
const DATA := {
    "pistol": {"name": "PISTOLA", "mag": 15, "interval": 0.22, "reload": 1.3, "damage": 22.0, "range": 110.0, "spread": 0.012, "pellets": 1, "kick": 0.10},
    "smg": {"name": "SMG", "mag": 30, "interval": 0.085, "reload": 1.9, "damage": 12.0, "range": 85.0, "spread": 0.029, "pellets": 1, "kick": 0.055},
    "rifle": {"name": "FUZIL", "mag": 30, "interval": 0.115, "reload": 2.2, "damage": 27.0, "range": 180.0, "spread": 0.014, "pellets": 1, "kick": 0.085},
    "shotgun": {"name": "ESCOPETA", "mag": 6, "interval": 0.85, "reload": 2.7, "damage": 11.0, "range": 45.0, "spread": 0.085, "pellets": 8, "kick": 0.19},
    "sniper": {"name": "SNIPER", "mag": 5, "interval": 1.3, "reload": 2.9, "damage": 95.0, "range": 300.0, "spread": 0.001, "pellets": 1, "kick": 0.23}
}
static func stats(weapon_id: String) -> Dictionary:
    return DATA.get(weapon_id, DATA["pistol"])
