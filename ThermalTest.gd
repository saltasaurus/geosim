extends Node

var thermal_grid: ThermalGrid
var auto_running = false
var step_count: int = 0
var timer: Timer

const TIME_STEP = 86400.0 * 365 * 1000  # 1000 year timesteps

func _ready():
	print("=== Thermal Grid + Darcy Flow Test ===")
	
	# Create and add thermal grid (not single column!)
	thermal_grid = ThermalGrid.new()
	add_child(thermal_grid)
	
	# Connect to signals for debugging
	thermal_grid.steep_density_gradient_detected.connect(_on_density_gradient_detected)
	thermal_grid.significant_material_flux_detected.connect(_on_material_flux_detected)
	
	# Create auto-run timer
	timer = Timer.new()
	timer.wait_time = 0.1  # Slower for debugging
	timer.timeout.connect(_on_timer_timeout)
	add_child(timer)
	
	# Wait for grid initialization
	await get_tree().create_timer(0.2).timeout
	
	print("\n=== Starting Grid Darcy Flow Test ===")
	# Test the new system
	test_darcy_flow_system()

func test_darcy_flow_system():
	"""Test the Darcy flow calculations"""
	print("\n=== Testing Darcy Flow System ===")
	
	# Run one update to see initial flux values
	thermal_grid.update_thermal_system()
	
	# Debug pressure gradients (now stores mass fluxes)
	debug_material_fluxes()

func debug_material_fluxes():
	"""Show material flux values across grid"""
	print("\n=== Material Flux Analysis ===")
	
	var max_flux = 0.0
	var total_flux = 0.0
	var flux_count = 0
	
	# Sample a few grid locations
	var sample_locations = [
		[5, 5], [10, 10], [15, 15],   # Diagonal samples
		[0, 10], [19, 10]              # Edge vs center
	]
	
	for location in sample_locations:
		var x = location[0]
		var y = location[1]
		var index = y * thermal_grid.grid_width + x
		
		if index < thermal_grid.pressure_gradients.size():
			var flux = thermal_grid.pressure_gradients[index]
			var flux_magnitude = flux.length()
			
			print("Location [", x, ",", y, "]:")
			print("  East flux: ", "%.9f" % flux.x, " kg/m²/s")
			print("  North flux: ", "%.9f" % flux.y, " kg/m²/s") 
			print("  Magnitude: ", "%.9f" % flux_magnitude, " kg/m²/s")
			print("  In mm/year: ", "%.9f" % (flux_magnitude * 31557600 * 1000), " mm/year")
			
			max_flux = max(max_flux, flux_magnitude)
			total_flux += flux_magnitude
			flux_count += 1
	
	print("\nFlux Summary:")
	print("  Maximum flux: ", "%.9f" % max_flux, " kg/m²/s")
	print("  Average flux: ", "%.9f" % (total_flux / flux_count), " kg/m²/s")
	
func _on_density_gradient_detected(location: Vector2, depth_km: float, gradient_mag: float, boundary_type: String):
	print("🔥 Steep gradient detected at [", location.x, ",", location.y, "] at ", depth_km, "km depth")
	print("   Gradient: ", "%.1f" % gradient_mag, " kg/m³/m (", boundary_type, ")")

func _on_material_flux_detected(source: Vector2, target: Vector2, depth_km: float, flux_rate: float):
	print("🌊 Significant flux: [", source.x, ",", source.y, "] → [", target.x, ",", target.y, "]")
	print("   Rate: ", "%.2f" % flux_rate, " kg/m²/s at ", depth_km, "km depth")

func start_auto_evolution():
	auto_running = true
	timer.start()
	print("Starting auto-evolution...")

func _on_timer_timeout():
	if not auto_running:
		return
	step_count += 1
	thermal_grid.update_thermal_system()
	
	if step_count % 5 == 0:  # Debug every 5 steps
		print("\n=== Step ", step_count, " ===")
		debug_material_fluxes()

func _input(event):
	if event.is_action_pressed("ui_accept"):  # Spacebar
		if auto_running:
			auto_running = false
			timer.stop()
			print("Auto-evolution paused")
		else:
			start_auto_evolution()
	elif event.is_action_pressed("ui_cancel"):  # Escape
		print("\n=== Final Results ===")
		debug_material_fluxes()
		get_tree().quit()
