extends RefCounted
## Weapon balance table. IDs follow keyboard slots 1-5.
## "range" is how far a bullet travels (past it the shot vanishes): long enough
## to hit anything you can see and aim at; accuracy at distance comes from "spread".
const ORDER := ["rifle", "sniper", "pistol", "shotgun", "smg", "bow"]
const DATA := {
    # Release-fired ballistic weapon; arrows are stored in reserve.
    "bow": {"name": "ARCO", "mag": 1, "interval": 0.35, "reload": 0.0, "damage": 55.0, "range": 120.0, "spread": 0.002, "pellets": 1, "kick": 0.0},
	"pistol": {"name": "PISTOLA", "mag": 15, "interval": 0.22, "reload": 1.3, "damage": 22.0, "range": 250.0, "spread": 0.012, "pellets": 1, "kick": 0.10},
	"smg": {"name": "SMG", "mag": 30, "interval": 0.085, "reload": 1.9, "damage": 12.0, "range": 220.0, "spread": 0.029, "pellets": 1, "kick": 0.055},
	"rifle": {"name": "FUZIL", "mag": 30, "interval": 0.115, "reload": 2.2, "damage": 27.0, "range": 450.0, "spread": 0.011, "pellets": 1, "kick": 0.085},
	"shotgun": {"name": "ESCOPETA", "mag": 6, "interval": 0.85, "reload": 2.7, "damage": 11.0, "range": 70.0, "spread": 0.085, "pellets": 8, "kick": 0.19},
	"sniper": {"name": "SNIPER", "mag": 5, "interval": 1.3, "reload": 2.9, "damage": 95.0, "range": 700.0, "spread": 0.001, "pellets": 1, "kick": 0.23}
}
## Mirando (botão direito) a dispersão cai para esta fração; agachado, um pouco mais.
const AIM_SPREAD := 0.22
const CROUCH_SPREAD := 0.8
static func stats(weapon_id: String) -> Dictionary:
	return DATA.get(weapon_id, DATA["pistol"])
