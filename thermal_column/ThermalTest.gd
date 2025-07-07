extends Node

var thermal_column: ThermalColumn
var auto_running = false
var step_count: int = 0

var timer: Timer

const TIME_STEP = 86400.0 * 365 * 10000

func _ready():
	print("=== Thermal Column Diffusion Test ===")
	
	# Create and add thermal column
	thermal_column = ThermalColumn.new()
	add_child(thermal_column)
	
	# Create an auto-run timer
	timer = Timer.new()
	timer.wait_time = 0.01
	timer.timeout.connect(_on_timer_timeout)
	add_child(timer)
	
	# Wait a moment for initialization, then run test
	await get_tree().create_timer(0.1).timeout
	
	print("\n=== Starting Diffusion Test ===")
	# 200 steps, 10000 year steps
	thermal_column.run_radioactive_heating_test(200, TIME_STEP)
	
func start_auto_evolution():
	auto_running = true
	timer.start()
	print("Starting autorun")
	
func cancel_auto_evolution():
	auto_running = false
	timer.stop()
	print("Autorun paused at step ", step_count, " (", step_count * 1000, " years)")
	
func _on_timer_timeout():
	if not auto_running:
		return
	step_count += 1
	thermal_column.update_temperatures(TIME_STEP)
	
	#if step_count % 10 == 0:
		#print("\n=== Step ", step_count, " (", step_count * 1000, " years) ===")
		#print("\n--- Stats ---")
		#for i in range(6):
			#print("Temp: %.1f" % thermal_column.temperatures[i*20], "| Velocity: %.2f" % thermal_column.vertical_velocity[i*20])
			#
	if step_count % 100 == 0:
		print("\n=== Step ", step_count, " (", step_count * 1000, " years) ===")
		thermal_column.get_density_info()
		thermal_column.get_buoyancy_info()
		thermal_column.get_velocity_info()
		thermal_column.get_advection_info()

func _input(event):
	if event.is_action_pressed("ui_accept"):  # Spacebar
		if auto_running:
			cancel_auto_evolution()
		else:
			start_auto_evolution()
	elif event.is_action_pressed("ui_cancel"):
		print("\n=== Final results after ", step_count * 1000, " years ===")
		thermal_column.get_density_info()
		thermal_column.get_buoyancy_info()
		thermal_column.get_velocity_info()
		get_tree().quit()
		#thermal_column.run_radioactive_heating_test(50, TIME_STEP)
