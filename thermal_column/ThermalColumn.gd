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

# Material properties (indexed by material ID)
# granite, basalt, mantle
var thermal_conductivity: Array[float] = [3.0, 2.0, 4.0]  # W/(m·K) for materials 0,1,2
var density: Array[float] = [2700, 3000, 3300]  # kg/m³
var heat_capacity: Array[float] = [1000, 1000, 1000]  # J/(kg·K)
var radioactive_heat_generation: Array[float] = [3.0e-6, 0.3e-6, 0.02e-6] # W/m³

func _ready():
	initialize_column()
	#create_hot_spot_test()
	create_mixed_materials_test()


func initialize_column():
	# Create depth array
	var num_layers = int(total_depth / layer_thickness) + 1
	depth_nodes.resize(num_layers)
	temperatures.resize(num_layers)
	materials.resize(num_layers)
	
	for i in range(num_layers):
		depth_nodes[i] = i * layer_thickness
		# Linear temperature profile for now
		temperatures[i] = surface_temp + (bottom_temp - surface_temp) * (float(i) / (num_layers - 1))
		materials[i] = 0  # Start with all granite for simplicity
	
	print("Initialized ", num_layers, " layers from 0 to ", total_depth/1000, "km")
	print("Surface temp: ", temperatures[0], "°C, Bottom temp: ", temperatures[temperatures.size()-1], "°C")

func create_mixed_materials_test():
	# Create a more interesting material distribution
	for i in range(materials.size()):
		if i >= 20 and i <= 30:  # 20-30km: basalt layer (low radioactivity)
			materials[i] = 1
		elif i >= 60 and i <= 80:  # 60-80km: mantle material (very low radioactivity) 
			materials[i] = 2
		else:
			materials[i] = 0  # Everything else: granite (high radioactivity)

	print("\nMixed materials test:")
	print("0-20km & 31-59km & 81-100km: Granite (", radioactive_heat_generation[0], " W/m³)")
	print("20-30km: Basalt (", radioactive_heat_generation[1], " W/m³)")  
	print("60-80km: Mantle (", radioactive_heat_generation[2], " W/m³)")
	print("This should create hot granite layers and cooler basalt/mantle layers!")

func create_hot_spot_test():
	# Add a hot anomaly at 50km depth
	#temperatures[50] = 1500.0  # Instead of the equilibrium 1007.5°C
	#print("\nHot spot test created:")
	#print("Layer 50 (50km): ", temperatures[50], "°C (should be ", surface_temp + (bottom_temp - surface_temp) * 0.5, "°C at equilibrium)")
	#print("Layer 49 (49km): ", temperatures[49], "°C")
	#print("Layer 51 (51km): ", temperatures[51], "°C")
	print("\nRadioactive heating test:")
	print("All layers using granite (material 0) with heat generation: ", radioactive_heat_generation[0], " W/m³")
	print("Starting from linear equilibrium profile...")
	print("Layer 25 (25km): ", "%.1f" % temperatures[25], "°C")
	print("Layer 50 (50km): ", "%.1f" % temperatures[50], "°C") 
	print("Layer 75 (75km): ", "%.1f" % temperatures[75], "°C")

func update_temperatures(dt: float):
	var new_temps = temperatures.duplicate()
	
	# Update interior layers (skip boundaries)
	for i in range(1, temperatures.size() - 1):
		var mat_id = materials[i]
		var alpha = thermal_conductivity[mat_id] / (density[mat_id] * heat_capacity[mat_id])
		
		# Heat diffusion term
		var diffusion = alpha * (temperatures[i-1] - 2*temperatures[i] + temperatures[i+1]) / (layer_thickness * layer_thickness)
		
		# Radioactive heating term
		var heat_source = radioactive_heat_generation[mat_id] / (density[mat_id] * heat_capacity[mat_id])
		
		# Combined temperature change
		new_temps[i] = temperatures[i] + dt * (diffusion + heat_source)
	
	# Keep boundaries fixed
	new_temps[0] = surface_temp
	new_temps[temperatures.size() - 1] = bottom_temp
	
	temperatures = new_temps
	
	## Debug output for hot spot area (only while anomaly exists)
	#if temperatures[50] > 1020:  # A bit above equilibrium
		#print("Time step - Layer 49: ", "%.1f" % temperatures[49], "°C, Layer 50: ", "%.1f" % temperatures[50], "°C, Layer 51: ", "%.1f" % temperatures[51], "°C")
	#
	## Debug output for radioactive heating effects
	#if temperatures[25] > 530 or temperatures[50] > 1020 or temperatures[75] > 1520:  # Above expected equilibrium
		#print("Radioactive heating - Layer 25: ", "%.1f" % temperatures[25], "°C, Layer 50: ", "%.1f" % temperatures[50], "°C, Layer 75: ", "%.1f" % temperatures[75], "°C")

# Test function to run multiple time steps
func run_diffusion_test(num_steps: int = 100, dt: float = 86400.0):  # dt = 1 day in seconds
	print("\nRunning diffusion for ", num_steps, " time steps (dt = ", dt/86400.0, " days)")
	
	for step in range(num_steps):
		update_temperatures(dt)
		
		# Print progress every 10 steps
		if step % 10 == 0:
			print("Step ", step, " - Hot spot temp: ", "%.1f" % temperatures[50], "°C")
	
	print("\nFinal temperatures around hot spot:")
	print("Layer 49: ", "%.1f" % temperatures[49], "°C")
	print("Layer 50: ", "%.1f" % temperatures[50], "°C") 
	print("Layer 51: ", "%.1f" % temperatures[51], "°C")
	print("Equilibrium should be: ", "%.1f" % (surface_temp + (bottom_temp - surface_temp) * 0.5), "°C")

# Test function to run multiple time steps
func run_radioactive_heating_test(num_steps: int = 200, dt: float = 86400.0 * 365 * 1000):  # dt = 1000 years
	print("\nRunning radioactive heating for ", num_steps, " time steps (dt = ", dt/(86400.0 * 365), " years)")
	print("Initial linear profile from ", surface_temp, "°C to ", bottom_temp, "°C")

	for step in range(num_steps):
		update_temperatures(dt)
		
		# Print progress every 20 steps
		if step % 20 == 0:
			print("Step ", step, " (", step * dt/(86400.0 * 365), " years) - Mid-column temp: ", "%.1f" % temperatures[50], "°C")

	print("\nFinal temperature profile with mixed radioactive heating:")
	print("Surface (0km): ", "%.1f" % temperatures[0], "°C")
	print("15km (granite): ", "%.1f" % temperatures[15], "°C")
	print("25km (basalt): ", "%.1f" % temperatures[25], "°C") 
	print("35km (granite): ", "%.1f" % temperatures[35], "°C")
	print("50km (granite): ", "%.1f" % temperatures[50], "°C")
	print("70km (mantle): ", "%.1f" % temperatures[70], "°C")
	print("90km (granite): ", "%.1f" % temperatures[90], "°C")
	print("Bottom (100km): ", "%.1f" % temperatures[100], "°C")
