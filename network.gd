# This source code is provided as reference/companion material for the Godot Multiplayer Setup tutorial
# that can be freely found at http://kehomsforge.com and should not be commercialized
# in any form. It should remain free!
#
# By Yuri Sarudiansky

extends Node

signal server_created                          # when server is successfully created
signal join_success                            # When the peer successfully joins a server
signal join_fail                               # Failed to join a server
signal player_list_changed                     # List of players has been changed
signal player_removed(pinfo)                   # A player has been removed from the list
signal disconnected                            # So outside code can act to disconnections from the server
signal ping_updated(peer, value)               # When the ping value has been updated
signal chat_message_received(msg)              # Whenever a chat message has been received - the msg argument is correctly formatted

var server_info = {
	name = "Server",      # Holds the name of the server
	max_players = 0,      # Maximum allowed connections
	used_port = 0         # Listening port
}

const ping_interval = 1.0           # Wait one second between ping requests
const ping_timeout = 5.0            # Wait 5 seconds before considering a ping request as lost

# This dictionary holds an entry for each connected player and will keep the necessary data to perform
# ping/pong requests. This will be filled only on the server
var ping_data = {}

var players = {}

# If bigger than 0, specifies the amount of simulated latency, in milliseconds
var fake_latency = 0

func _ready():
	get_tree().connect("network_peer_connected", self, "_on_player_connected")
	get_tree().connect("network_peer_disconnected", self, "_on_player_disconnected")
	get_tree().connect("connected_to_server", self, "_on_connected_to_server")
	get_tree().connect("connection_failed", self, "_on_connection_failed")
	get_tree().connect("server_disconnected", self, "_on_disconnected_from_server")


func create_server():
	# Initialize the networking system
	var net = NetworkedMultiplayerENet.new()
	
	# Try to create the server
	if (net.create_server(server_info.used_port, server_info.max_players) != OK):
		print("Failed to create server")
		return
	
	# Assign it into the tree
	get_tree().set_network_peer(net)
	# Tell the server has been created successfully
	emit_signal("server_created")
	# Register the server's player in the local player list
	register_player(gamestate.player_info)


func join_server(ip, port):
	var net = NetworkedMultiplayerENet.new()
	
	if (net.create_client(ip, port) != OK):
		print("Failed to create client")
		emit_signal("join_fail")
		return
		
	get_tree().set_network_peer(net)


func kick_player(net_id, reason):
	# First remote call the function that will give the reason to the kicked player
	rpc_id(net_id, "kicked", reason)
	# Then disconnect that player from the server
	get_tree().network_peer.disconnect_peer(net_id)


### Event handlers

# Everyone gets notified whenever a new client joins the server
func _on_player_connected(id):
	if (get_tree().is_network_server()):
		# Send the server info to the player
		rpc_id(id, "get_server_info", server_info)
		
		# Initialize the ping data entry
		var ping_entry = {
			timer = Timer.new(),          # Timer object to control the ping/pong loop
			signature = 0,                # Used to match ping/pong packets
			packet_lost = 0,              # Count number of lost packets
			last_ping = 0,                # Last measured time taken to get an answer from the peer
		}
		
		# Setup the timer
		ping_entry.timer.one_shot = true
		ping_entry.timer.wait_time = ping_interval
		ping_entry.timer.process_mode = Timer.TIMER_PROCESS_IDLE
		ping_entry.timer.connect("timeout", self, "_on_ping_interval", [id], CONNECT_ONESHOT)
		ping_entry.timer.set_name("ping_timer_" + str(id))
		
		# Timers need to be part of the tree otherwise they are not updated and never fire up the timeout event
		add_child(ping_entry.timer)
		# Add the entry to the dictionary
		ping_data[id] = ping_entry
		# Just to ensure, start the timer (in theory is should run but...)
		ping_entry.timer.start()


# Everyone gets notified whenever someone disconnects from the server
func _on_player_disconnected(id):
	print("Player ", players[id].name, " disconnected from server")
	# Update the player tables
	if (get_tree().is_network_server()):
		# Make sure the timer is stoped
		ping_data[id].timer.stop()
		# Remove the timer from the tree
		ping_data[id].timer.queue_free()
		# And from the ping_data dictionary
		ping_data.erase(id)
		
		# Unregister the player from the server's list
		unregister_player(id)
		# Then on all remaining peers
		rpc("unregister_player", id)


# Peer trying to connect to server is notified on success
func _on_connected_to_server():
	emit_signal("join_success")
	# Update the player_info dictionary with the obtained unique network ID
	gamestate.player_info.net_id = get_tree().get_network_unique_id()
	# Request the server to register this new player across all connected players
	rpc_id(1, "register_player", gamestate.player_info)
	# And register itself on the local list
	register_player(gamestate.player_info)


# Peer trying to connect to server is notified on failure
func _on_connection_failed():
	emit_signal("join_fail")
	get_tree().set_network_peer(null)


# Peer is notified when disconnected from server
func _on_disconnected_from_server():
	print("Disconnected from server")
	# Stop processing any node in the world, so the client remains responsive
	get_tree().paused = true
	# Clear the network object
	get_tree().set_network_peer(null)
	# Allow outside code to know about the disconnection
	emit_signal("disconnected")
	# Clear the internal player list
	players.clear()
	# Reset the player info network ID
	gamestate.player_info.net_id = 1


### Remote functions
remote func register_player(pinfo):
	if (fake_latency > 0):
		yield(get_tree().create_timer(fake_latency / 1000), "timeout")
	
	if (get_tree().is_network_server()):
		# We are on the server, so distribute the player list information throughout the connected players
		for id in players:
			# Send currently iterated player info to the new player
			rpc_id(pinfo.net_id, "register_player", players[id])
			# Send new player info to currently iterated player, skipping the server (which will get the info shortly)
			if (id != 1):
				rpc_id(id, "register_player", pinfo)
	
	# Now to code that will be executed regardless of being on client or server
	print("Registering player ", pinfo.name, " (", pinfo.net_id, ") to internal player table")
	players[pinfo.net_id] = pinfo          # Create the player entry in the dictionary
	emit_signal("player_list_changed")     # And notify that the player list has been changed


remote func unregister_player(id):
	if (fake_latency > 0):
		yield(get_tree().create_timer(fake_latency / 1000), "timeout")

	print("Removing player ", players[id].name, " from internal table")
	# Cache the player info because it's still necessary for some upkeeping
	var pinfo = players[id]
	# Remove the player from the list
	players.erase(id)
	# And notify the list has been changed
	emit_signal("player_list_changed")
	# Emit the signal that is meant to be intercepted only by the server
	emit_signal("player_removed", pinfo)


remote func get_server_info(sinfo):
	if (fake_latency > 0):
		yield(get_tree().create_timer(fake_latency / 1000), "timeout")
	
	if (!get_tree().is_network_server()):
		server_info = sinfo


remote func kicked(reason):
	if (fake_latency > 0):
		yield(get_tree().create_timer(fake_latency / 1000), "timeout")
	
	print("You have been kicked from the server, reason: ", reason)


### Manual latency measurement

func request_ping(dest_id):
	# Configure the timer
	ping_data[dest_id].timer.connect("timeout", self, "_on_ping_timeout", [dest_id], CONNECT_ONESHOT)
	# Start the timer
	ping_data[dest_id].timer.start(ping_timeout)
	# Call the remote machine
	rpc_unreliable_id(dest_id, "on_ping", ping_data[dest_id].signature, ping_data[dest_id].last_ping)


remote func on_ping(signature, last_ping):
	if (fake_latency > 0):
		yield(get_tree().create_timer(fake_latency / 1000), "timeout")
	
	# Call the server back
	rpc_unreliable_id(1, "on_pong", signature)
	# Tell this client that there is a new measured ping value - yes, this corresponds to the last request
	emit_signal("ping_updated", get_tree().get_network_unique_id(), last_ping)


#remote func on_pong(peer_id, signature):
remote func on_pong(signature):
	if (fake_latency > 0):
		yield(get_tree().create_timer(fake_latency / 1000), "timeout")
	
	# Bail if not the server
	if (!get_tree().is_network_server()):
		return
	
	# Obtain the unique ID of the caller
	var peer_id = get_tree().get_rpc_sender_id()
	
	# Check if the answer matches the expected one
	if (ping_data[peer_id].signature == signature):
		# It does. Calculate the elapsed time, in milliseconds
		ping_data[peer_id].last_ping = (ping_timeout - ping_data[peer_id].timer.time_left) * 1000
		# If here, the ping timeout timer is running but must be configured now for the ping interval
		ping_data[peer_id].timer.stop()
		ping_data[peer_id].timer.disconnect("timeout", self, "_on_ping_timeout")
		ping_data[peer_id].timer.connect("timeout", self, "_on_ping_interval", [peer_id], CONNECT_ONESHOT)
		ping_data[peer_id].timer.start(ping_interval)
		# Broadcast the new value to everyone
		rpc_unreliable("ping_value_changed", peer_id, ping_data[peer_id].last_ping)
		# And allow the server to do something with this value
		emit_signal("ping_updated", peer_id, ping_data[peer_id].last_ping)


remote func ping_value_changed(peer_id, value):
	if (fake_latency > 0):
		yield(get_tree().create_timer(fake_latency / 1000), "timeout")
	
	emit_signal("ping_updated", peer_id, value)


func _on_ping_timeout(peer_id):
	print("Ping timeout, destination peer ", peer_id)
	# The last ping request has timedout. No answer received, so assume the packet has been lost
	ping_data[peer_id].packet_lost += 1
	# Update the ping signature that will be sent in the next request
	ping_data[peer_id].signature += 1
	# And request a new ping - no need to wait since we have already waited 5 seconds!
	call_deferred("request_ping", peer_id)


func _on_ping_interval(peer_id):
	# Update the ping signature then request it
	ping_data[peer_id].signature += 1
	request_ping(peer_id)


### Chat system
remote func send_message(src_id, msg, broadcast):
	if (fake_latency > 0):
		yield(get_tree().create_timer(fake_latency / 1000), "timeout")
	
	if (get_tree().is_network_server()):
		if (broadcast):
			for id in players:
				# Skip sender because it already handles the message, which has different formatting
				# Skip the server because it will handle itself after exiting the server-only section
				if (id != src_id && id != 1):
					rpc_id(id, "send_message", src_id, msg, broadcast)
		
		# Now that the message has been broadcast, check if the source is the server. If so, skip the rest
		# otherwise the mesage will appear twice on the chat box. One with the "everyone" formatting and the
		# other with the local formatting
		if (src_id == 1):
			return
	
	# Everyone section. First, format the message. Prefix it with the name of the sender
	var final_msg = "[" + players[src_id].name + "]: " + msg
	emit_signal("chat_message_received", final_msg)


func get_player_id(player_name):
	for id in players:
		if (players[id].name == player_name):
			return id
	
	# If here the player has not been found. Return an invalid ID
	return 0

