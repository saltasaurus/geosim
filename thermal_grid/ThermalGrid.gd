class_name ThermalGrid extends Node2D

var grid_width: int = 20
var grid_height: int = 20
var thermal_columns: Array  # 2D array of ThermalColumn
var boundary_type: BoundaryType = BoundaryType.PERIODIC

enum BoundaryType { PERIODIC, FIXED, ISLAND }

func _ready():
	print("Initializing ", grid_width, "x", grid_height, " thermal grid")
	initialize_grid()
	print("Grid initialization complete")
	
func initialize_grid():
	thermal_columns.resize(grid_width)
	for x in range(grid_width):
		thermal_columns[x] = []
		thermal_columns[x].resize(grid_height)
		for y in range(grid_height):
			var column = ThermalColumn.new()
			thermal_columns[x][y] = column
			add_child(column)
			
			print("Created column [", x, ",", y, "]")

	print("Created ", grid_width * grid_height, " thermal columns")
