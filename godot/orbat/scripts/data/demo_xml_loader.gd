extends RefCounted
class_name DemoXmlLoader


static func load_assets_xml(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("DemoXmlLoader: empty or missing file: %s" % path)
		return {}
	text = _strip_xml_declaration(text)

	var p := XMLParser.new()
	if p.open_buffer(text.to_utf8_buffer()) != OK:
		push_error("DemoXmlLoader: cannot parse XML: %s" % path)
		return {}

	var assets: Dictionary = {}
	var current: AssetDefinition = null

	while p.read() == OK:
		match p.get_node_type():
			XMLParser.NODE_ELEMENT:
				var el := String(p.get_node_name())
				if el == "asset":
					current = AssetDefinition.new()
					current.id = _attr(p, "id")
					current.asset_type = _attr(p, "type")
					current.display_name = _attr(p, "display_name")
				elif current != null:
					match el:
						"stats":
							current.stats_mass = _attr_float(p, "mass", 0.0)
							current.stats_durability = _attr_float(p, "durability", 0.0)
						"visual":
							current.visual_scene = _attr(p, "scene")
						"weapon":
							current.projectile_scene = _attr(p, "projectile_scene")
							current.fire_rate = _attr_float(p, "fire_rate", 0.0)
							current.projectile_speed = _attr_float(p, "projectile_speed", 0.0)
							current.weapon_range = _attr_float(p, "range", 0.0)
			XMLParser.NODE_ELEMENT_END:
				if String(p.get_node_name()) == "asset" and current != null:
					if not current.id.is_empty():
						assets[current.id] = current
					current = null

	return assets


static func load_units_xml(path: String, assets: Dictionary) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("DemoXmlLoader: empty or missing file: %s" % path)
		return {}
	text = _strip_xml_declaration(text)

	var p := XMLParser.new()
	if p.open_buffer(text.to_utf8_buffer()) != OK:
		push_error("DemoXmlLoader: cannot parse XML: %s" % path)
		return {}

	var units: Dictionary = {}
	var u: UnitDefinition = null
	var platform_visual: String = ""
	var weapon: AssetDefinition = null

	while p.read() == OK:
		match p.get_node_type():
			XMLParser.NODE_ELEMENT:
				var el := String(p.get_node_name())
				if el == "unit":
					u = UnitDefinition.new()
					u.id = _attr(p, "id")
					u.display_name = _attr(p, "display_name")
					platform_visual = ""
					weapon = null
				elif u != null and el == "runtime":
					u.team = _attr(p, "team")
					u.hp = int(_attr_float(p, "hp", 1.0))
					u.move_speed = _attr_float(p, "move_speed", 1.0)
					u.aggro_range = _attr_float(p, "aggro_range", 1.0)
					u.attack_range = _attr_float(p, "attack_range", 1.0)
					u.respawn_sec = _attr_float(p, "respawn_sec", 1.0)
				elif u != null and el == "asset_ref":
					var rid := _attr(p, "id")
					var role := _attr(p, "role")
					var req := _attr(p, "required", "false").to_lower() == "true"
					if rid.is_empty():
						continue
					if not assets.has(rid):
						if req:
							push_error("DemoXmlLoader: missing asset id '%s' for unit '%s'" % [rid, u.id])
						continue
					var ad: AssetDefinition = assets[rid]
					match role:
						"platform":
							if ad.is_core():
								platform_visual = ad.visual_scene
						"primary_weapon":
							if ad.is_weapon():
								weapon = ad
			XMLParser.NODE_ELEMENT_END:
				if String(p.get_node_name()) == "unit" and u != null:
					_finish_unit(u, platform_visual, weapon)
					if not u.id.is_empty():
						units[u.id] = u
					u = null

	return units


static func _finish_unit(unit: UnitDefinition, platform_visual: String, w: AssetDefinition) -> void:
	unit.visual_scene = platform_visual
	if w != null and w.is_weapon():
		unit.weapon_projectile_scene = w.projectile_scene
		unit.fire_rate = w.fire_rate
		unit.projectile_speed = w.projectile_speed
		unit.weapon_range = w.weapon_range
	if unit.attack_range <= 0.0 and unit.weapon_range > 0.0:
		unit.attack_range = unit.weapon_range


static func _attr(p: XMLParser, key: String, default: String = "") -> String:
	for i in range(p.get_attribute_count()):
		if String(p.get_attribute_name(i)) == key:
			return String(p.get_attribute_value(i))
	return default


static func _attr_float(p: XMLParser, key: String, default: float) -> float:
	var s := _attr(p, key, "")
	if s.is_empty():
		return default
	return float(s)


static func _strip_xml_declaration(text: String) -> String:
	var t := text.strip_edges()
	if t.begins_with("<?xml"):
		var close := t.find("?>")
		if close != -1:
			t = t.substr(close + 2).strip_edges()
	return t
