class_name ThermalColumn extends Node

# Core data arrays (GPU-friendly flat arrays)
var depth_nodes: PackedFloat32Array
var temperatures: PackedFloat32Array
var materials: PackedInt32Array

# Physical constants
var surface_temp: float = 15.0    # °C
var baseline_flux: float = 0.030  # mW/m^2
var layer_thickness: float = 1000.0  # meters (1km layers)
var total_depth: float = 100000.0    # meters (100km)
#var base_viscosity: Array[float] = [1e23, 1e22, 1e20]  # NEW: Pa·s for granite, basalt, mantle
var base_viscosity: Array[float] = [1e15, 1e14, 1e12] # Adjusted for faster simulation
var reference_mantle_geotherm: float

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

# Flags
var advection_enabled: bool = false # Enable/disable material movement

func _ready():
	initialize_column()
	create_realistic_earth_test()
	enable_advection()

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
		material_displacement[i] = 0.0 # No initial displacement
	
	# Calculate initial densities and forces
	set_realistic_materials()
	calculate_steady_state_geotherm()
	update_densities()
	calculate_reference_densities()
	calculate_buoyancy_forces()
	calculate_velocities()
	
	reference_mantle_geotherm = temperatures[temperatures.size() - 1]
	
	#print("Initialized ", num_layers, " layers from 0 to ", total_depth/1000, "km")
	#print("Surface temp: ", temperatures[0], "°C, Bottom temp: ", temperatures[temperatures.size()-1], "°C")

func set_realistic_materials():
	"""Set materials based on depth - continental crust model"""
	
	for i in range(materials.size()):
		if depth_nodes[i] < 40_000: # 0-40km: Continental crust
			materials[i] = 0 		# Granite
		else:						# 40km+: Upper mantle
			materials[i] = 2		# Peridotite

func calculate_steady_state_geotherm():
	"""Calculates the initial steady state temperatures based on layer materials"""
	
	# Pass 1: Calculate heat flux (bottom to top)
	var heat_flux = PackedFloat32Array()
	heat_flux.resize(temperatures.size())
	
	# Start with baseline heat flux from deeper Earth (observed)
	#var baseline_flux = 30.0 # mW/m² typical mantle heat flux
	heat_flux[heat_flux.size()-1] = baseline_flux # / 1000.0 # Convert to W/m²
	
	# Work upwards, accumulating radioactive heat
	for i in range(heat_flux.size()-2, -1, -1):
		var material_id = materials[i+1] # Material in layer BELOW
		var heat_added = radioactive_heat_generation[material_id] * layer_thickness
		heat_flux[i] = heat_flux[i+1] + heat_added
		
	# Pass 2: Calculate temperatures (top to bottom)
	temperatures[0] = surface_temp # Fixed surface temp (assume surface can release all addition energy)
	
	for i in range(1, temperatures.size()):
		var material_id = materials[i]
		var temp_increase = heat_flux[i] * layer_thickness / thermal_conductivity[material_id]
		temperatures[i] = temperatures[i-1] + temp_increase

	#print("Two-pass geotherm calculated")
	#print("Surface: ", "%.1f" % temperatures[0], "°C")
	#print("40km: ", "%.1f" % temperatures[40], "°C") 
	#print("Bottom: ", "%.1f" % temperatures[100], "°C")
	
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
	
	# Step 1: Calculate upward flux for each layer
	var upward_flux = PackedFloat32Array()
	upward_flux.resize(temperatures.size())
	
	for i in range(upward_flux.size()):
		if vertical_velocity[i] > 0: # Only positive (upward) velocities create upward flux
			var flux_fraction: float = vertical_velocity[i] * dt / layer_thickness
			
			# Stability constraint: limit 10% of layer per timestep
			# Could be calculated based on strain rate limits or CFL conditions
			var limited_flux = min(flux_fraction, 0.1)
			upward_flux[i] = limited_flux
			
			#if i == 20 or i == 40 or i == 60:
				#print("DEBUG Layer ", i, ": velocity=", "%.9f" % vertical_velocity[i], " flux_raw=", "%.6f" % flux_fraction, " flux_limited=", "%.6f" % limited_flux)
		else:
			upward_flux[i] = 0.0 # No upward flux for downward/stationary material
	
	var max_flux = 0.0
	for i in range(upward_flux.size()):
		max_flux = max(max_flux, upward_flux[i])
	
	#print("DEBUG: Max upward flux = ", "%.6f" % max_flux)		
	
	# Step 2: Apply flux transfers
	apply_flux_transfers(upward_flux, dt)
	
func apply_flux_transfers(upward_flux: PackedFloat32Array, dt: float):
	var new_temperatures = temperatures.duplicate()
	var new_materials = materials.duplicate()
	
	# Step 1: Apply upward material transfers
	for i in range(1, upward_flux.size(), - 1): # Skip boundaries
		if upward_flux[i] > 0:
			# Material floating out of layer i
			var outflow_material_fraction = upward_flux[i]
			var outflow_temp = temperatures[i] * outflow_material_fraction
			
			# Remove source layer
			new_temperatures[i] -= outflow_temp
			
			# Add to destination layer (above)
			new_temperatures[i-1] += outflow_temp
			
			# Handle material transfer
			# Can use mixed material calculations for viscosity 
			if outflow_material_fraction > 0.5:
				new_materials[i-1] = materials[i]
				
	# Step 2: replenish bottom layer with fresh mantle
	var total_upward_flux: float = 0.0
	for i in range(upward_flux.size()):
		total_upward_flux += upward_flux[i]
		
	var adjusted_temp_and_material = replenish_bottom_boundary(new_temperatures, new_materials, total_upward_flux)

	# Step 3: Update arrays
	temperatures = adjusted_temp_and_material[0]
	materials = adjusted_temp_and_material[1]
	
func replenish_bottom_boundary(new_temperatures: PackedFloat32Array, new_materials: PackedInt32Array, total_upward_flux: float):
	"""Bottom replenishment for any gaps (1D solution)"""
	
	# Replemenish bottom layers with fresh mantle material
	if total_upward_flux > 0:
		var bottom_index = new_materials.size() - 1
		
		# Add fresh mantle material
		new_materials[bottom_index] = 2 # Mantle material
		
		# Fresh mantle enters at reference temperature for that depth
		var fresh_mantle_temp = reference_mantle_geotherm
		
		# Mix with any existing material
		var mixing_fraction = min(total_upward_flux, 0.3) # Limit mixing rate
		new_temperatures[bottom_index] = (1.0 - mixing_fraction) * new_temperatures[bottom_index] + mixing_fraction * fresh_mantle_temp
		
	# Ensure bottom boundary maintains heat flux
	new_temperatures = apply_bottom_heat_flux_boundary(new_temperatures)
	
	return [new_temperatures, new_materials]
	
func apply_bottom_heat_flux_boundary(temps: PackedFloat32Array):
	var bottom_index = temps.size() - 1
	var bottom_material_id = materials[bottom_index]
	
	var temp_drop = (baseline_flux * layer_thickness) / thermal_conductivity[bottom_material_id]
	temps[bottom_index] = temps[bottom_index-1] + temp_drop # Temperature drops from above temperature
	
	return temps
	
func debug_material_tracking():
	#print("\nMaterial Debug - Material Movement:")
	
	var granite_count = 0
	var mantle_count: int = 0
	
	for i in range(40):
		if materials[i] == 0: granite_count += 1
		#else: print("Mantle found at ", i, "km depth!")
		
	for i in range(40, materials.size()):
		if materials[i] == 2: mantle_count += 1
		#else: print("Granite found at ", i, "km depth!")
	
	#print("Granite in upper 40km: ", granite_count, "/40")
	#print("Mantle in lower 60km: ", mantle_count, "/61")
			
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
	
	#print("\nRealistic Earth structure:")
	#print("0-40km: Continental crust (granite) - high radioactive heating")
	#print("40-100km: Upper mantle (peridotite) - very low radioactive heating")
	#print("This should create hot crust and cooler mantle - perfect for convection!")
	#print("Material 1 (basalt) available for future volcanic processes")

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
		var mat_id = materials[i]
		var temp = temperatures[i]
		var temp_factor = exp(-temp / 1000.0)
		var effective_viscosity = base_viscosity[mat_id] * temp_factor
		print("Effective viscosity: ", "%.9f" % effective_viscosity, " Pa*s")

func enable_advection():
	advection_enabled = true
	#print("\n=== ADVECTION ENABLED ===")
	#print("Material will now move based on buoyancy forces!")
	#print("Watch for temperature and material redistribution...")
	
func get_advection_info():
	# Show flux-based movement instead of displacement
	print("\nFlux-Based Advection Analysis:")

	# Calculate current flux values for display
	var current_flux = PackedFloat32Array()
	current_flux.resize(vertical_velocity.size())

	for i in range(vertical_velocity.size()):
		if vertical_velocity[i] > 0:
			var flux_fraction = vertical_velocity[i] * (86400.0 * 365 * 1000) / layer_thickness  # Use 1000-year dt
			current_flux[i] = min(flux_fraction, 0.1)
		else:
			current_flux[i] = 0.0

	print("Current upward flux rates:")
	print("20km: ", "%.4f" % current_flux[20], " (", "%.1f" % (current_flux[20] * 100), "% of layer per 1000 years)")
	print("40km: ", "%.4f" % current_flux[40], " (", "%.1f" % (current_flux[40] * 100), "% of layer per 1000 years)")
	print("60km: ", "%.4f" % current_flux[60], " (", "%.1f" % (current_flux[60] * 100), "% of layer per 1000 years)")

	# Show actual material redistribution
	print("\nMaterial boundaries:")
	debug_material_tracking()

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
	
	# Top temperature boundary
	new_temps[0] = surface_temp
	# Bottom heat flux boundary
	var bottom_index = temperatures.size() - 1
	#var baseline_flux = 0.030  # Same value as initialization
	var temp_drop = (baseline_flux * layer_thickness) / thermal_conductivity[materials[bottom_index]]
	new_temps[bottom_index] = new_temps[bottom_index-1] + temp_drop
	
	temperatures = new_temps
	
	# Update densities after temperature changes
	update_densities()
	calculate_buoyancy_forces()
	calculate_velocities()
	
	if advection_enabled:
		advect_material(dt)

func get_lateral_pressure(depth_index: int) -> float:
	"""Get pressure at specific depth for neighbor calculations"""
	
	# Calculate pressure from weight of overlying material
	var pressure: float = 0.0
	for i in range(depth_index + 1):
		pressure += actual_density[i] * GRAVITY * layer_thickness
		
	return pressure
	
func receive_later_material_flux(
	source_depth: int,
	target_depth: int,
	material_type: int,
	mass_flux_kg_per_m2: float,
	flux_temperature: float
):
	"""Receive material from a neighboring column"""
	print("Column received flux: ", mass_flux_kg_per_m2, " kg/m2 of material ", material_type, " at ", flux_temperature, "C")
	
func send_material_flux_info() -> Dictionary:
	"""Provide information needed for flux calculations"""
	return {
		"pressures": get_all_pressures(),
		"temperatures": temperatures.duplicate(),
		"materials": materials.duplicate(),
		"densities": actual_density.duplicate()
	}

func get_all_pressures() -> PackedFloat32Array:
	"""Calculate pressure at each depth
	
	Hydrostatic Pressure Field: P(z) = P₀ + Σ(ρᵢ × g × Δz)
	"""
	var pressures = PackedFloat32Array()
	pressures.resize(depth_nodes.size())

	pressures[0] = 0.0  # Surface pressure
	for i in range(1, pressures.size()):
		var layer_weight = actual_density[i-1] * GRAVITY * layer_thickness
		pressures[i] = pressures[i-1] + layer_weight

	return pressures
