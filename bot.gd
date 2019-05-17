# This source code is provided as reference/companion material for the Godot Multiplayer Setup tutorial
# that can be freely found at http://kehomsforge.com and should not be commercialized
# in any form. It should remain free!
#
# By Yuri Sarudiansky

extends Node2D

const speed_range = Vector2(150, 300)
var dest_location = Vector2()
onready var screen_limits = get_viewport_rect().size
var start_pos = Vector2()
var count_time = 0
var current_time = 0

# Replicated data
slave var repl_position = Vector2()
slave var repl_rotation = 0.0


func _ready():
	# Calculate a random modulation color - randf() gives a random number in the interval [0,1]
	$icon.modulate = Color(randf(), randf(), randf())
	# And a random position - ideally this initial position should be placed on the spawn code
	# however simplicity is required for the tutorial
	position = get_random_location()
	# And the motion variables
	calculate_motion_vars()


func _process(delta):
	if (is_network_master()):
		current_time += delta
		var alpha = current_time / count_time
		if (alpha > 1.0):
			alpha = 1.0
		
		var nposition = start_pos.linear_interpolate(dest_location, alpha)
		
		if (alpha >= 1.0):
			calculate_motion_vars()
		
		position = nposition
		
		# Replicate values
		rset("repl_position", position)
		rset("repl_rotation", rotation)
	else:
		position = repl_position
		rotation = repl_rotation


func get_random_location():
	var limits = get_viewport_rect().size
	return Vector2(rand_range(0, limits.x), rand_range(0, limits.y))


func calculate_motion_vars():
	dest_location = get_random_location()
	count_time = position.distance_to(dest_location) / rand_range(speed_range.x, speed_range.y)
	current_time = 0
	start_pos = position
	var angle = get_angle_to(dest_location) + (PI/2)   # Angle is in radians
	rotate(angle)

