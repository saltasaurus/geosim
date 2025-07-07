extends Node

var thermal_column: ThermalColumn

const TIME_STEP = 86400.0 * 365 * 10000

func _ready():
	print("=== Thermal Column Diffusion Test ===")
	
	# Create and add thermal column
	thermal_column = ThermalColumn.new()
	add_child(thermal_column)
	
	# Wait a moment for initialization, then run test
	await get_tree().create_timer(0.1).timeout
	
	print("\n=== Starting Diffusion Test ===")
	# 200 steps, 1000 year steps
	thermal_column.run_radioactive_heating_test(200, TIME_STEP)

func _input(event):
	if event.is_action_pressed("ui_accept"):  # Spacebar
		print("\n=== Running another 50 steps ===")
		#thermal_column.run_diffusion_test(50, TIME_STEP)
		thermal_column.run_radioactive_heating_test(50, TIME_STEP)
