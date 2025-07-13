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
			configure_column_location(column, x, y)
			
			thermal_columns[x][y] = column
			add_child(column) # Calls _ready()
			
			print("Created column [", x, ",", y, "]")

	print("Created ", grid_width * grid_height, " thermal columns")
	
func configure_column_location(column: ThermalColumn, x: int, y: int):
	# Simple gradient: cold on left (0°C), hot on right (30°C)
	var temperature_factor = float(x) / float(grid_width - 1)
	column.surface_temp = 0.0 + (30.0 * temperature_factor)

	print("Configuring column [", x, ",", y, "] surface temp: ", "%.1f" % column.surface_temp, "°C")
	
func calculate_lateral_pressure_differences():
	"""Calculate pressure differences that drive lateral material flow"""
	print("\n=== Calculating lateral pressure differences ===")
	
	# Check pressure differences between a few neighbor pairs
	
	var example_pairs = [
		[5, 5, 6, 5],		# Column [5,5] vs [6,5] (eastward)
		[5, 5, 5, 6], 		# Column [5,5] vs [5,6] (northward)
		[10, 10, 11, 10],	# Column [10,10] vs [11,10] (eastward)
		[10, 10, 10, 11]	# Column [10, 10] vs [10, 11] (eastward)
	]

	for pair in example_pairs:
		var x1 = pair[0]
		var y1 = pair[1]
		var x2 = pair[2]
		var y2 = pair[3]
		
		# Get pressure info from both columns
		var thermal_col1: ThermalColumn = thermal_columns[x1][y1]
		var col1_info = thermal_col1.send_material_flux_info()
		
		var thermal_col2: ThermalColumn = thermal_columns[x2][y2]
		var col2_info = thermal_col2.send_material_flux_info()
		
		var pressures1 = col1_info["pressures"]
		var pressures2 = col2_info["pressures"]
		
		# Compare pressures at same depths
		var depth_indices_to_check = [10, 20, 40, 60, 100]
		
		print("Pressure comparison [", x1, ",", y1, "] vs [", x2, ",", y2, "]:")
		for depth_idx in depth_indices_to_check:
			if depth_idx < pressures1.size() and depth_idx < pressures2.size():
				#print("Pressure 1: ", pressures1[depth_idx], " | Pressure 2: ", pressures2[depth_idx])
				var pressure_diff = pressures1[depth_idx] - pressures2[depth_idx]
				
				print("  ", depth_idx, "km: ", "%.2f" % (pressure_diff/1e6), " MPa difference")
				
				if abs(pressure_diff) > 1e6:  # > 1 MPa difference
					var flow_direction = "-->" if pressure_diff > 0 else "<--"
					print("    Material wants to flow: ", flow_direction)

func update_thermal_system():
	"""Main update function - will coordinate all thermal processes"""
	
	# Step 1: All columns update their internal thermal state
	for x in range(grid_width):
		for y in range(grid_height):
			thermal_columns[x][y].update_densities()
			thermal_columns[x][y].calculate_buoyancy_forces()
			thermal_columns[x][y].calculate_velocities()
	
	# Step 2: Calculate lateral interactions
	calculate_lateral_pressure_differences()
	
	print("Thermal system update complete")
