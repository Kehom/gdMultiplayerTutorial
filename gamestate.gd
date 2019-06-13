# This source code is provided as reference/companion material for the Godot Multiplayer Setup tutorial
# that can be freely found at http://kehomsforge.com and should not be commercialized
# in any form. It should remain free!
#
# By Yuri Sarudiansky

extends Node

signal snapshot_received(snapshot)    # Emitted as soon as an snapshot is fully decoded

var player_info = {
	name = "Player",                   # How this player will be shown within the GUI
	net_id = 1,                        # By default everyone receives "server" ID
	actor_path = "res://player.tscn",  # The class used to represent the player in the game world
	char_color = Color(1, 1, 1),       # By default don't modulate the icon color
}

var spawned_bots = 0
var bot_info = {}

# If this is true, then player input will be gathered and processed. Otherwise "ignored"
var accept_player_input = true

var update_rate = 30 setget set_update_rate                          # How many game updates per second
var update_delta = 1.0 / update_rate setget no_set, get_update_delta # And the delta time for the specified update rate


# Cache the variant headers so we can manually decode data sent across the network
var int_header = PoolByteArray(var2bytes(int(0)).subarray(0, 3))
var float_header = PoolByteArray(var2bytes(float(0)).subarray(0, 3))
var vec2_header = PoolByteArray(var2bytes(Vector2()).subarray(0, 3))
var col_header = PoolByteArray(var2bytes(Color()).subarray(0, 3))
var bool_header = PoolByteArray(var2bytes(bool(false)).subarray(0, 6))

# The "signature" (timestamp) added into each generated state snapshot
var snapshot_signature = 1
# The signature of the last snapshot received
var last_snapshot = 0

# Holds player input data (including the local one) which will be used to update the game state
# This will be filled only on the server
var player_input = {}


func _ready():
	randomize()
	
	# Initialize the bot list
	for id in range(1, 16):
		bot_info[id] = { name = "Bot_" + str(id), actor_path = "res://bot.tscn" }


func set_update_rate(r):
	update_rate = r
	update_delta = 1.0 / update_rate


func get_update_delta():
	return update_delta


func no_set(r):
	pass


# Encode a variable that uses 4 bytes (integer, float)
func encode_4bytes(val):
	return var2bytes(val).subarray(4, 7)


# Encode a variable that uses 8 bytes (vector2)
func encode_8bytes(val):
	return var2bytes(val).subarray(4, 11)


# Encode a variable that uses 12 bytes (vector3...)
func encode_12bytes(val):
	return var2bytes(val).subarray(4, 15)


# Encode a variable that uses 16 bytes (quaternion, color...)
func encode_16bytes(val):
	return var2bytes(val).subarray(4, 19)


# Based on the "High level" snapshot data, encodes into a byte array
# ready to be sent across the network. This function does not return
# the data, just broadcasts it to the connected players. To that end,
# it is meant to be run only on the server
func encode_snapshot(snapshot_data):
	if (!get_tree().is_network_server()):
		return
	
	var encoded = PoolByteArray()
	
	# First add the snapshot signature (timestamp)
	encoded.append_array(encode_4bytes(snapshot_data.signature))
	
	# Player data count
	encoded.append_array(encode_4bytes(snapshot_data.player_data.size()))
	# snapshot_data should contain a "players" field which must be an array
	# of player data. Each entry in this array should be a dictionary, containing
	# the following fields: network_id, location, rot, col
	for pdata in snapshot_data.player_data:
		# Encode the network_id which should be an integer, 4 bytes
		encoded.append_array(encode_4bytes(pdata.net_id))
		# Encode the location which should be a Vector2, 8 bytes
		encoded.append_array(encode_8bytes(pdata.location))
		# Encode the rotation which should be a float, 4 bytes
		encoded.append_array(encode_4bytes(pdata.rot))
		# Encode the color which should be a Color, 16 bytes
		encoded.append_array(encode_16bytes(pdata.col))
	
	# Bot data count
	encoded.append_array(encode_4bytes(snapshot_data.bot_data.size()))
	# The bot_data field should be an array, each entry containing the following
	# fields: bot_id, location, rot, col
	for bdata in snapshot_data.bot_data:
		# Encode the bot_id which should be an integer, 4 bytes
		encoded.append_array(encode_4bytes(bdata.bot_id))
		# Encode the location, which should be a vector2, 8 bytes
		encoded.append_array(encode_8bytes(bdata.location))
		# Encode the rotation which should be a float, 4 bytes
		encoded.append_array(encode_4bytes(bdata.rot))
		# Encode the color which should be a Color, 16 bytes
		encoded.append_array(encode_16bytes(bdata.col))
	
	# Snapshot fully encoded. Time to broadcast it
	rpc_unreliable("client_get_snapshot", encoded)


func cache_input(p_id, data):
	if (!get_tree().is_network_server()):
		return
	
	if (!player_input.has(p_id)):
		player_input[p_id] = []
	
	player_input[p_id].append(data)


remote func client_get_snapshot(encoded):
	if (network.fake_latency > 0):
		yield(get_tree().create_timer(network.fake_latency / 1000), "timeout")
	
	var decoded = {
		# Extract the signature
		signature = bytes2var(int_header + encoded.subarray(0, 3)),
		# Initialize the player data and bot data arrays
		player_data = [],
		bot_data = [],
	}
	
	# If the received snapshot is older (or even equal) to the last received one, ignore the rest
	if (decoded.signature <= last_snapshot):
		return
	
	# Control variable to point into the byte array (skipping player count)
	var idx = 8
	
	# Extract player data count
	var pdata_count = bytes2var(int_header + encoded.subarray(4, 7))
	# Then the player data itself
	for i in range(pdata_count):
		# Extract the network ID, integer, 4 bytes
		var eid = bytes2var(int_header + encoded.subarray(idx, idx + 3))
		idx += 4
		# Extract the location, Vector2, 8 bytes
		var eloc = bytes2var(vec2_header + encoded.subarray(idx, idx + 7))
		idx += 8
		# Extract rotation, float, 4 bytes
		var erot = bytes2var(float_header + encoded.subarray(idx, idx + 3))
		idx += 4
		# Extract color, Color, 16 bytes
		var ecol = bytes2var(col_header + encoded.subarray(idx, idx + 15))
		idx += 16
		
		var pd = {
			net_id = eid,
			location = eloc,
			rot = erot,
			col = ecol,
		}
		
		decoded.player_data.append(pd)
	
	# Extract bot data count
	var bdata_count = bytes2var(int_header + encoded.subarray(idx, idx + 3))
	idx += 4
	# Then the bot data
	for i in range(bdata_count):
		# Extract the bot id
		var bid = bytes2var(int_header + encoded.subarray(idx, idx + 3))
		idx += 4
		# Extract the location
		var eloc = bytes2var(vec2_header + encoded.subarray(idx, idx + 7))
		idx += 8
		# Extract rotation
		var erot = bytes2var(float_header + encoded.subarray(idx, idx + 3))
		idx += 4
		# Extract color
		var ecol = bytes2var(col_header + encoded.subarray(idx, idx + 15))
		idx += 16
		
		var bd = {
			bot_id = bid,
			location = eloc,
			rot = erot,
			col = ecol
		}
		
		decoded.bot_data.append(bd)
	
	# Update the "last_snapshot"
	last_snapshot = decoded.signature
	# Emit the signal indicating that there is a new snapshot do be applied
	emit_signal("snapshot_received", decoded)

