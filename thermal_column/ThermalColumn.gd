class_name ThermalColumn extends Node

# Core data arrays (GPU-friendly flat arrays)
var depth_nodes: PackedFloat32Array
var temperatures: PackedFloat32Array
var materials: PackedInt32Array

# Physical constants
var surface_temp: float = 15.0    # °C
var bottom_temp: float = 2000.0   # °C
var layer_thickness: float = 1000.0  # meters (1km layers)
var total_depth: float = 100000.0    # meters (100km)
var base_viscosity: Array[float] = [1e23, 1e22, 1e20]  # NEW: Pa·s for granite, basalt, mantle

# Material properties (indexed by material ID)
var thermal_conductivity: Array[float] = [3.0, 2.0, 4.0]  # W/(m·K) for materials 0,1,2
var base_density: Array[float] = [2700, 3000, 3300]  # kg/m³ at reference temperature
var heat_capacity: Array[float] = [1000, 1000, 1000]  # J/(kg·K)
var radioactive_heat_generation: Array[float] = [3.0e-6, 0.3e-6, 0.02e-6]  # W/m³ (granite, basalt, mantle)
var thermal_expansion_coeff: Array[float] = [3.0e-5, 2.8e-5, 3.2e-5]  # /°C (granite, basalt, mantle)

# Dynamic properties (calculated each timestep)
var actual_density: PackedFloat32Array  # Current density including thermal expansion
var reference_density: PackedFloat32Array  # What density should be at each depth (hydrostatic)
var buoyancy_force: PackedFloat32Array  # Buoyancy force per unit volume (N/m³)
var reference_temperature: float = 0.0  # °C - reference temp for density calculations
var vertical_velocity: PackedFloat32Array  # NEW: Vertical velocity (m/s)
var material_displacement: PackedFloat32Array  # How far each layer has moved from original position

# Physical constants
var GRAVITY: float = 9.81  # m/s²
var advection_enabled: bool = false # Enable/disable material movement

func _ready():
	initialize_column()
	create_realistic_earth_test()

func initialize_column():
	# Create depth array
	var num_layers = int(total_depth / layer_thickness) + 1
	depth_nodes.resize(num_layers)
	temperatures.resize(num_layers)
	materials.resize(num_layers)
	actual_density.resize(num_layers)
	reference_density.resize(num_layers)
	buoyancy_force.resize(num_layers)
	vertical_velocity.resize(num_layers)
	material_displacement.resize(num_layers)
	
	for i in range(num_layers):
		depth_nodes[i] = i * layer_thickness
		# Linear temperature profile for now
		temperatures[i] = surface_temp + (bottom_temp - surface_temp) * (float(i) / (num_layers - 1))
		materials[i] = 0  # Start with all granite for simplicity
		material_displacement[i] = 0.0 # No initial displacement
	
	# Calculate initial densities and forces
	update_densities()
	calculate_reference_densities()
	calculate_buoyancy_forces()
	calculate_velocities()
	
	print("Initialized ", num_layers, " layers from 0 to ", total_depth/1000, "km")
	print("Surface temp: ", temperatures[0], "°C, Bottom temp: ", temperatures[temperatures.size()-1], "°C")

func update_densities():
	# Calculate actual density based on temperature using thermal expansion
	for i in range(actual_density.size()):
		var mat_id = materials[i]
		var temp_diff = temperatures[i] - reference_temperature
		
		# Thermal expansion: ρ(T) = ρ₀ × [1 - α × (T - T₀)]
		actual_density[i] = base_density[mat_id] * (1.0 - thermal_expansion_coeff[mat_id] * temp_diff)

func calculate_reference_densities():
	# Calculate what density should be at each depth assuming hydrostatic equilibrium
	# For now, use a simple linear increase with depth based on pressure
	for i in range(reference_density.size()):
		var depth = depth_nodes[i]
		var mat_id = materials[i]
		
		# Simple approximation: density increases with pressure
		# Real Earth: ~1% density increase per 10km depth due to compression
		var pressure_factor = 1.0 + (depth / 100000.0) * 0.1  # 10% increase over 100km
		reference_density[i] = base_density[mat_id] * pressure_factor

func calculate_buoyancy_forces():
	# Calculate buoyancy force: F = (ρ_ref - ρ_actual) × g
	for i in range(buoyancy_force.size()):
		buoyancy_force[i] = (reference_density[i] - actual_density[i]) * GRAVITY
		
func calculate_velocities():
	for i in range(vertical_velocity.size()):
		var mat_id = materials[i]
		var temp = temperatures[i]

		# Hot material flows easier (lower viscosity)
		var temp_factor = exp(-temp / 1000.0)  # Exponential temperature dependence
		var effective_viscosity = base_viscosity[mat_id] * temp_factor

		# Stokes flow: velocity = force / viscosity
		vertical_velocity[i] = buoyancy_force[i] / effective_viscosity
		
func advect_material(dt: float):
	"""Move material based on velocity and update properties"""
	
	# Update displacements
	for i in range(material_displacement.size()):
		material_displacement[i] += vertical_velocity[i] * dt
		
	# Create new property array based on material movement
	var new_temperatures = PackedFloat32Array()
	var new_materials = PackedInt32Array()
	new_temperatures.resize(temperatures.size())
	new_materials.resize(materials.size())
	
	# For each point, find new material at location
	for i in range(temperatures.size()):
		var current_depth = depth_nodes[i]
		
		# Find which original layer's material is now at this depth
		var source_layer = find_source_layer_at_depth(current_depth)
		
		# Copy properties from the source layer
		if source_layer >= 0 and source_layer < temperatures.size():
			new_temperatures[i] = temperatures[source_layer]
			new_materials[i] = materials[source_layer]
		else:
			# Boundary handling
			new_temperatures[i] = temperatures[i]
			new_materials[i] = materials[i]
			
	# Update arrays with advected properties
	temperatures = new_temperatures
	materials = new_materials
	
func find_source_layer_at_depth(target_depth: float) -> int:
	"""Find which original layer's material has moved to the target depth"""	
		
	var best_match: int = -1
	var min_distance = 1e9
	
	for i in range(depth_nodes.size()):
		# Calculate where this layer's material has moved
		var original_depth = depth_nodes[i]
		var current_material_depth = original_depth + material_displacement[i]
		
		# Find the closest match to our target depth
		var distance = abs(current_material_depth - target_depth)
		if distance < min_distance:
			min_distance = distance
			best_match = i
		
	
	return best_match
		
func get_density_info():
	# Debug function to show density changes
	print("\nDensity Analysis:")
	print("Surface (", "%.0f" % temperatures[0], "°C): ", "%.0f" % actual_density[0], " kg/m³ (granite)")
	print("20km (", "%.0f" % temperatures[20], "°C): ", "%.0f" % actual_density[20], " kg/m³ (granite)")
	print("40km (", "%.0f" % temperatures[40], "°C): ", "%.0f" % actual_density[40], " kg/m³ (mantle)")
	print("60km (", "%.0f" % temperatures[60], "°C): ", "%.0f" % actual_density[60], " kg/m³ (mantle)")
	print("80km (", "%.0f" % temperatures[80], "°C): ", "%.0f" % actual_density[80], " kg/m³ (mantle)")
	print("Bottom (", "%.0f" % temperatures[100], "°C): ", "%.0f" % actual_density[100], " kg/m³ (mantle)")

func create_realistic_earth_test():
	# Standard Earth structure - continental crust over mantle
	for i in range(materials.size()):
		var depth = depth_nodes[i]
		if depth < 40000:  # 0-40km: Continental crust
			materials[i] = 0  # Granite
		else:               # 40km+: Upper mantle
			materials[i] = 2  # Peridotite (mantle rock)
			
	print(materials[20], materials[40], )
	
	print("\nRealistic Earth structure:")
	print("0-40km: Continental crust (granite) - high radioactive heating")
	print("40-100km: Upper mantle (peridotite) - very low radioactive heating")
	print("This should create hot crust and cooler mantle - perfect for convection!")
	print("Material 1 (basalt) available for future volcanic processes")

func get_buoyancy_info():
	# Debug function to show buoyancy forces
	print("\nBuoyancy Analysis:")
	print("20km (crust): ", "%.1f" % buoyancy_force[20], " N/m³ (", "positive = wants to rise" if buoyancy_force[20] > 0 else "negative = wants to sink", ")")
	print("40km (boundary): ", "%.1f" % buoyancy_force[40], " N/m³")
	print("60km (mantle): ", "%.1f" % buoyancy_force[60], " N/m³")
	print("80km (mantle): ", "%.1f" % buoyancy_force[80], " N/m³")
	
func get_velocity_info():
	print("\nVelocity Analysis:")
	# Convert m/s values to geological mm/year for readability
	for i in range(5):
		var layer: int = i * 20
		print(layer, " km velocity: ", vertical_velocity[layer], " m/s = ", vertical_velocity[layer] * 31557600000, " mm/year")

func enable_advection():
	advection_enabled = true
	print("\n=== ADVECTION ENABLED ===")
	print("Material will now move based on buoyancy forces!")
	print("Watch for temperature and material redistribution...")
	
func get_advection_info():
	# Debug function to show material movement
	print("\nAdvection Analysis:")
	print("20km displacement: ", "%.2f" % material_displacement[20], " meters (", "%.2f" % (material_displacement[20]/1000), " km)")
	print("40km displacement: ", "%.2f" % material_displacement[40], " meters (", "%.2f" % (material_displacement[40]/1000), " km)")
	print("60km displacement: ", "%.2f" % material_displacement[60], " meters (", "%.2f" % (material_displacement[60]/1000), " km)")
	print("80km displacement: ", "%.2f" % material_displacement[80], " meters (", "%.2f" % (material_displacement[80]/1000), " km)")

	# Check for material boundary changes
	var crust_layers = 0
	var mantle_layers = 0
	for i in range(40):  # First 40 layers should be crust
		if materials[i] == 0: crust_layers += 1
	for i in range(40, materials.size()):  # Remaining should be mantle
		if materials[i] == 2: mantle_layers += 1

	print("Crust layers in upper 40km: ", crust_layers, "/40")
	print("Mantle layers in lower region: ", mantle_layers, "/", materials.size() - 40)


func update_temperatures(dt: float):
	"""Main function. Updates temperatures, which causes all other processes to begin"""
	var new_temps = temperatures.duplicate()
	
	# Update interior layers (skip boundaries)
	for i in range(1, temperatures.size() - 1):
		var mat_id = materials[i]
		var alpha = thermal_conductivity[mat_id] / (base_density[mat_id] * heat_capacity[mat_id])
		
		# Heat diffusion term
		var diffusion = alpha * (temperatures[i-1] - 2*temperatures[i] + temperatures[i+1]) / (layer_thickness * layer_thickness)
		
		# Radioactive heat generation term
		var heat_source = radioactive_heat_generation[mat_id] / (base_density[mat_id] * heat_capacity[mat_id])
		
		# Combined temperature change
		new_temps[i] = temperatures[i] + dt * (diffusion + heat_source)
	
	# Keep boundaries fixed
	new_temps[0] = surface_temp
	new_temps[temperatures.size() - 1] = bottom_temp
	
	temperatures = new_temps
	
	# Update densities after temperature changes
	update_densities()
	calculate_buoyancy_forces()
	calculate_velocities()
	
	if advection_enabled:
		advect_material(dt)
	
	## Debug output for radioactive heating effects
	#if temperatures[25] > 530 or temperatures[50] > 1020 or temperatures[75] > 1520:  # Above expected equilibrium
		#print("Radioactive heating - Layer 25: ", "%.1f" % temperatures[25], "°C, Layer 50: ", "%.1f" % temperatures[50], "°C, Layer 75: ", "%.1f" % temperatures[75], "°C")

# Test function to run multiple time steps
func run_radioactive_heating_test(num_steps: int = 200, dt: float = 86400.0 * 365 * 1000):  # dt = 1000 years
	print("\nRunning radioactive heating for ", num_steps, " time steps (dt = ", dt/(86400.0 * 365), " years)")
	print("Initial linear profile from ", surface_temp, "°C to ", bottom_temp, "°C")
	
	for step in range(num_steps):
		update_temperatures(dt)
		
		# Print progress every 20 steps
		if step % 20 == 0:
			print("Step ", step, " (", step * dt/(86400.0 * 365), " years) - Mid-column temp: ", "%.1f" % temperatures[50], "°C")
	
	print("\nFinal realistic Earth temperature profile:")
	print("Surface (0km): ", "%.1f" % temperatures[0], "°C")
	print("20km (crust): ", "%.1f" % temperatures[20], "°C")
	print("40km (crust-mantle boundary): ", "%.1f" % temperatures[40], "°C") 
	print("60km (mantle): ", "%.1f" % temperatures[60], "°C")
	print("80km (mantle): ", "%.1f" % temperatures[80], "°C")
	print("Bottom (100km): ", "%.1f" % temperatures[100], "°C")
	
	# Show density changes
	get_density_info()
	
	# Show buoyancy forces
	get_buoyancy_info()
	
	# Show velocities
	get_velocity_info()
