class_name ThermalGrid extends Node2D

# Emergent physics signals
signal steep_density_gradient_detected(location: Vector2, depth_km: float, gradient_magnitude: float, boundary_type: String)
signal significant_material_flux_detected(source: Vector2, target: Vector2, depth_km: float, flux_rate: float)
signal pressure_anomaly_detected(location: Vector2, depth_km: float, pressure_excess: float)

var grid_width: int = 20
var grid_height: int = 20
var total_size: int
var thermal_columns: Array  # 2D array of ThermalColumn
var boundary_type: BoundaryType = BoundaryType.PERIODIC
var boundary_scan_counter: int = 0

var active_boundaries: Array[Dictionary] = [] # Cache discovered boundaries
var pressure_gradients: PackedVector2Array
var column_spacing: float = 1000.0

enum BoundaryType { PERIODIC, FIXED, ISLAND }

func _ready():
	print("Initializing ", grid_width, "x", grid_height, " thermal grid")
	initialize_grid()
	initialize_pressure_gradients()
	print("Grid initialization complete")
	
func initialize_grid():
	thermal_columns.resize(grid_width)
	total_size = grid_width * grid_height
	
	for x in range(grid_width):
		thermal_columns[x] = []
		thermal_columns[x].resize(grid_height)
		for y in range(grid_height):
			var column = ThermalColumn.new()
			configure_column_location(column, x, y)
			
			thermal_columns[x][y] = column
			add_child(column) # Calls _ready()
			
			print("Created column [", x, ",", y, "]")

	print("Created ", total_size, " thermal columns")

func initialize_pressure_gradients():
	"""Initialize the pressure gradient array"""
	
	pressure_gradients.resize(total_size)
	
	# Initialize all gradients to zero
	for i in range(total_size):
		pressure_gradients[i] = Vector2.ZERO
	
	print("Pressure gradient field initialized: ", total_size, " Vector2 elements")
	
func configure_column_location(column: ThermalColumn, x: int, y: int):
	# Simple gradient: cold on left (0°C), hot on right (30°C)
	var temperature_factor = float(x) / float(grid_width - 1)
	column.surface_temp = 0.0 + (30.0 * temperature_factor)

	print("Configuring column [", x, ",", y, "] surface temp: ", "%.1f" % column.surface_temp, "°C")

func update_thermal_system():
	"""Main update function - will coordinate all thermal processes"""
	
	# Step 1: All columns update their internal thermal state
	for x in range(grid_width):
		for y in range(grid_height):
			thermal_columns[x][y].update_densities()
			thermal_columns[x][y].calculate_buoyancy_forces()
			thermal_columns[x][y].calculate_velocities()
			
	# Scan for boundary changes every 10 timesteps
	boundary_scan_counter += 1
	if boundary_scan_counter >= 10:
		boundary_scan_counter = 0
		scan_for_density_boundaries()
	
	# Step 2: Calculate lateral interactions from pressure gradients and Darcy flow
	calculate_pressure_gradients_with_darcy_flow()
	
	print("Thermal system update complete")
	
func scan_for_density_boundaries():
	"""Find all significant density boundaries in the grid"""
	active_boundaries.clear()
	
	for x in range(grid_width):
		for y in range(grid_height):
			var column: ThermalColumn = thermal_columns[x][y]
			var boundaries = column.find_steep_density_gradients(50.0)
			
			for boundary in boundaries:
				boundary["grid_location"] = Vector2(x, y)
				active_boundaries.append(boundary)
				
				# Emit signal for external systems
				steep_density_gradient_detected.emit(
					Vector2(x, y),
					boundary["depth_km"],
					boundary["density_gradient"],
					boundary["boundary_type"]
				)
	
func calculate_pressure_gradients_with_darcy_flow():
	"""Calculate pressure differences and material flux at critical depths"""

	# Always calculate at column bottom (lithostatic pressure)
	calculate_darcy_flow_at_depth(-1)  # -1 = bottom depth

	# Calculate at each discovered boundary
	for boundary in active_boundaries:
		var location: Vector2 = boundary["grid_location"]
		var depth_index: int = boundary["depth_index"]
		calculate_darcy_flow_at_location(location, depth_index)

func calculate_interface_flux(x1: int, y1: int, x2: int, y2: int, depth_index: int):
	"""Calculate mass flux from column [x1,y1] to column [x2,y2]"""

	var col1_info = thermal_columns[x1][y1].send_material_flux_info()
	var col2_info = thermal_columns[x2][y2].send_material_flux_info()

	# Handle bottom depth (-1)
	var target_depth = depth_index if depth_index >=  0 else col1_info["pressures"].size() - 1

	var pressure_diff = col1_info["pressures"][target_depth] - col2_info["pressures"][target_depth]
	var pressure_gradient = pressure_diff / column_spacing

	# Darcy flow
	var material_id = col1_info["materials"][target_depth]
	var density = col1_info["densities"][target_depth] 
	var viscosity = get_effective_viscosity(material_id, target_depth, x1, y1)
	var permeability = 1e-15

	var velocity = (permeability / viscosity) * pressure_gradient
	var mass_flux = velocity * density

	return mass_flux  # Positive = flow from col1 to col2

func calculate_darcy_flow_at_depth(depth_index: int):
	"""Calculate darcy flow at a single location and depth"""
	
	# Initialize net flux arrays
	var net_fluxes = PackedVector2Array()
	net_fluxes.resize(total_size)
	for i in range(net_fluxes.size()):
		net_fluxes[i] = Vector2.ZERO
		
	# Calculate all horizontal interfaces (east-west)
	for x in range(grid_width):
		for y in range(grid_height):
			var east_x = (x + 1) % grid_width  # Wrap-around
			var flux = calculate_interface_flux(x, y, east_x, y, depth_index)

			var current_index = y * grid_width + x
			var east_index = y * grid_width + east_x

			# Apply flux as outflow/inflow pair
			net_fluxes[current_index].x -= flux    # Outflow from current
			net_fluxes[east_index].x += flux       # Inflow to eastern neighbor

	# Calculate all vertical interfaces (north-south)
	for x in range(grid_width):
		for y in range(grid_height):
			var north_y = (y + 1) % grid_height  # Wrap-around
			var flux = calculate_interface_flux(x, y, x, north_y, depth_index)

			var current_index = y * grid_width + x
			var north_index = north_y * grid_width + x

			# Apply flux as outflow/inflow pair
			net_fluxes[current_index].y -= flux    # Outflow from current
			net_fluxes[north_index].y += flux      # Inflow to northern neighbor

	pressure_gradients = net_fluxes

func calculate_darcy_flow_at_location(location: Vector2, depth_index: int):
	"""Calculate material flux using Darcy flow at specified depth"""

	var x: int = int(location.x)
	var y: int = int(location.y)

	# Calculate fluxes for all 4 interfaces touching this location
	var east_x: int = (x + 1) % grid_width
	var west_x: int = (x - 1 + grid_width) % grid_width
	var north_y: int = (y + 1) % grid_height
	var south_y: int = (y - 1 + grid_height) % grid_height

	var current_index: int = y * grid_width + x
	var net_flux = Vector2.ZERO

	# East interface
	var flux_east = calculate_interface_flux(x, y, east_x, y, depth_index)
	net_flux.x -= flux_east

	# West interface  
	var flux_west = calculate_interface_flux(west_x, y, x, y, depth_index)
	net_flux.x += flux_west

	# North interface
	var flux_north = calculate_interface_flux(x, y, x, north_y, depth_index)
	net_flux.y -= flux_north

	# South interface
	var flux_south = calculate_interface_flux(x, south_y, x, y, depth_index)
	net_flux.y += flux_south

	pressure_gradients[current_index] = net_flux

func get_effective_viscosity(material_id: int, depth_index: int, x: int, y: int) -> float:
	"""Get viscosity for material at specific location"""
	var column = thermal_columns[x][y]
	var temperature = column.temperatures[depth_index]
	var base_visc = column.base_viscosity[material_id]
	return base_visc * exp(-temperature / 1000.0)
