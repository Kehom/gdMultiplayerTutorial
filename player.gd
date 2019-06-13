# This source code is provided as reference/companion material for the Godot Multiplayer Setup tutorial
# that can be freely found at http://kehomsforge.com and should not be commercialized
# in any form. It should remain free!
#
# By Yuri Sarudiansky

extends Node2D


var move_speed = 300
onready var current_time = 0         # Used to count input timeouts


func _process(delta):
	# Update the timeout counter and if "outside of the update window", bail
	current_time += delta
	if (current_time < gamestate.update_delta):
		return
	
	# Inside an "input" window. First "reset" the time counting variable.
	# Rather than just resetting to 0, subtract update_delta from it to try to compensate
	# for some variances in the time counting. Ideally it would be a good idea to check if the
	# current_time is still bigger than update_delta after this subtraction which would indicate
	# some major lag in the game
	current_time -= gamestate.update_delta
	
	if (is_network_master() && gamestate.accept_player_input):
		gather_input()


func set_dominant_color(color):
	$icon.modulate = color


func gather_input():
	var input_data = {
		up = Input.is_action_pressed("move_up"),
		down = Input.is_action_pressed("move_down"),
		left = Input.is_action_pressed("move_left"),
		right = Input.is_action_pressed("move_right"),
		mouse_pos = get_global_mouse_position(),
	}
	
	if (get_tree().is_network_server()):
		# On the server, direcly cache the input data
		#cache_input(1, input_data, float(gamestate.input_rate))
		gamestate.cache_input(1, input_data)
	else:
		# On a client. Encode the data and send to the server
		var encoded = PoolByteArray()
		encoded.append(input_data.up)
		encoded.append(input_data.down)
		encoded.append(input_data.left)
		encoded.append(input_data.right)
		encoded.append_array(gamestate.encode_8bytes(input_data.mouse_pos))
		rpc_unreliable_id(1, "server_get_player_input", encoded)


remote func server_get_player_input(input):
	if (network.fake_latency > 0):
		yield(get_tree().create_timer(network.fake_latency / 1000), "timeout")
		
	if (get_tree().is_network_server()):
		# Decode the input data
		var input_data = {
			up = bytes2var(gamestate.bool_header + input.subarray(0, 0)),
			down = bytes2var(gamestate.bool_header + input.subarray(1, 1)),
			left = bytes2var(gamestate.bool_header + input.subarray(2, 2)),
			right = bytes2var(gamestate.bool_header + input.subarray(3, 3)),
			mouse_pos = bytes2var(gamestate.vec2_header + input.subarray(4, 11)),
		}
		# Then cache the decoded data
		gamestate.cache_input(get_tree().get_rpc_sender_id(), input_data)


#remote func client_get_player_update(pos):
#	if (network.fake_latency > 0):
#		yield(get_tree().create_timer(network.fake_latency / 1000), "timeout")
#
#	position = pos

