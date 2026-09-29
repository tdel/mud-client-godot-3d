extends SceneTree
## Outil de contrôle : compte les arbres dessinés (instances de MultiMesh de Vegetation, dans
## la carte / dans la bande visuelle hors carte) et les cases par terrain d'une scène de carte.
##   godot --headless --path . --script res://tools/map_gen/count_vegetation.gd -- <scène.tscn>

var _frames := 0
var _root: Node


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		_root = (load(OS.get_cmdline_user_args()[0]) as PackedScene).instantiate()
		root.add_child(_root)
		return false
	var grid: GridMap = _root.get_node("Terrain")
	var width := 0
	var height := 0
	var by_terrain := {}
	for cell in grid.get_used_cells():
		width = maxi(width, cell.x + 1)
		height = maxi(height, cell.z + 1)
		var t := grid.mesh_library.get_item_name(grid.get_cell_item(cell))
		by_terrain[t] = by_terrain.get(t, 0) + 1
	var inside := 0
	var outside := 0
	var decor := {}
	for mmi in _root.get_node("Vegetation").find_children("*", "MultiMeshInstance3D", true, false):
		var mm: MultiMesh = mmi.multimesh
		var mesh_name := String(mmi.name).split("_", false)
		var key := "_".join(mesh_name.slice(0, mesh_name.size() - 2))
		# Relu sur le buffer : le serveur de rendu factice (--headless) ne rend pas les
		# transformations par instance.
		var buffer := mm.buffer
		for i in mm.instance_count:
			var o := Vector3(buffer[i * 12 + 3], buffer[i * 12 + 7], buffer[i * 12 + 11])
			if key.begins_with("tree_"):
				if o.x >= 0 and o.z >= 0 and o.x < width and o.z < height:
					inside += 1
				else:
					outside += 1
			else:
				decor[key] = decor.get(key, 0) + 1
	print("Cases par terrain : %s" % str(by_terrain))
	print("Arbres dessinés : %d dans la carte, %d hors carte" % [inside, outside])
	print("Décor : %s" % str(decor))
	quit()
	return true
