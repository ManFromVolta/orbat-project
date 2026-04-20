extends RefCounted
class_name AssetDefinition

var id: String = ""
var asset_type: String = ""
var display_name: String = ""
var visual_scene: String = ""
var stats_mass: float = 0.0
var stats_durability: float = 0.0
var projectile_scene: String = ""
var fire_rate: float = 0.0
var projectile_speed: float = 0.0
var weapon_range: float = 0.0

func is_weapon() -> bool:
	return asset_type == "weapon"

func is_core() -> bool:
	return asset_type == "core"
