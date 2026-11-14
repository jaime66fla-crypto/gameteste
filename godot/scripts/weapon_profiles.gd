extends RefCounted
## Tunable pre-release prototype weapon profiles.
const ORDER := ["pistol", "rifle", "shotgun", "sniper"]
const PROFILES := {
    "pistol": {"label": "PISTOLA", "mag": 15, "delay": 0.22, "reload": 1.3, "pellets": 1, "spread": 0.008, "range": 140.0, "recoil": 0.11, "length": 0.50, "stock": false},
    "rifle": {"label": "FUZIL", "mag": 30, "delay": 0.095, "reload": 1.9, "pellets": 1, "spread": 0.013, "range": 180.0, "recoil": 0.075, "length": 0.90, "stock": true},
    "shotgun": {"label": "ESCOPETA", "mag": 8, "delay": 0.75, "reload": 2.3, "pellets": 8, "spread": 0.085, "range": 48.0, "recoil": 0.19, "length": 0.78, "stock": true},
    "sniper": {"label": "SNIPER", "mag": 5, "delay": 1.15, "reload": 2.6, "pellets": 1, "spread": 0.001, "range": 300.0, "recoil": 0.23, "length": 1.20, "stock": true}
}

static func profile(id: String) -> Dictionary:
    return PROFILES.get(id, PROFILES["pistol"])

static func index_to_id(index: int) -> String:
    return ORDER[clampi(index, 0, ORDER.size() - 1)]
