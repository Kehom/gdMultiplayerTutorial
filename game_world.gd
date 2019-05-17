# This source code is provided as reference/companion material for the Godot Multiplayer Setup tutorial
# that can be freely found at http://kehomsforge.com and should not be commercialized
# in any form. It should remain free!
#
# By Yuri Sarudiansky

extends Node2D


func _ready():
	# Connect event handler to the player_list_changed signal
	network.connect("player_list_changed", self, "_on_player_list_changed")
	# If we are in the server, connect to the event that will deal with player despawning
	if (get_tree().is_network_server()):
		network.connect("player_removed", self, "_on_player_removed")
	
	# Update the lblLocalPlayer label widget to display the local player name
	$HUD/PanelPlayerList/lblLocalPlayer.text = gamestate.player_info.name
	
	# Spawn the players
	if (get_tree().is_network_server()):
		spawn_players(gamestate.player_info, 1)
		sync_bots(-1)    # The amount doesn't matter because it will be calculated in the function body
	else:
		rpc_id(1, "spawn_players", gamestate.player_info, -1)
		rpc_id(1, "sync_bots", -1)


func _on_player_list_changed():
	print("Got the player_list_changed event")
	
	# First remove all children from the boxList widget
	for c in $HUD/PanelPlayerList/boxList.get_children():
		c.queue_free()
	
	# Now iterate through the player list creating a new entry into the boxList
	for p in network.players:
		if (p != gamestate.player_info.net_id):
			var nlabel = Label.new()
			nlabel.text = network.players[p].name
			$HUD/PanelPlayerList/boxList.add_child(nlabel)


func _on_player_removed(pinfo):
	despawn_player(pinfo)
	sync_bots(-1)       # Again, amount doesn't matter at this point because the server side section will take care of it


# Spawns a new player actor, using the provided player_info structure and the given spawn index
remote func spawn_players(pinfo, spawn_index):
	# If the spawn_index is -1 then we define it based on the size of the player list
	if (spawn_index == -1):
		spawn_index = network.players.size()
	
	if (get_tree().is_network_server() && pinfo.net_id != 1):
		# We are on the server and the requested spawn does not belong to the server
		# Iterate through the connected players
		var s_index = 1      # Will be used as spawn index
		for id in network.players:
			# Spawn currently iterated player within the new player's scene, skipping the new player for now
			if (id != pinfo.net_id):
				rpc_id(pinfo.net_id, "spawn_players", network.players[id], s_index)
			
			# Spawn the new player within the currently iterated player as long it's not the server
			# Because the server's list already contains the new player, that one will also get itself!
			if (id != 1):
				rpc_id(id, "spawn_players", pinfo, spawn_index)
			
			s_index += 1
	
	print("Spawning actor for player ", pinfo.name, "(", pinfo.net_id, ") - ", spawn_index)
	
	# Load the scene and create an instance
	var pclass = load(pinfo.actor_path)
	var nactor = pclass.instance()
	# Setup player customization (well, the color)
	nactor.set_dominant_color(pinfo.char_color)
	# And the actor position
	nactor.position = $SpawnPoints.get_node(str(spawn_index)).position
	# If this actor does not belong to the server, change the node name and network master accordingly
	if (pinfo.net_id != 1):
		nactor.set_network_master(pinfo.net_id)
		nactor.set_name(str(pinfo.net_id))
	# Finally add the actor into the world
	add_child(nactor)


remote func despawn_player(pinfo):
	if (get_tree().is_network_server()):
		for id in network.players:
			# Skip disconnecte player and server from replication code
			if (id == pinfo.net_id || id == 1):
				continue
			
			# Replicate despawn into currently iterated player
			rpc_id(id, "despawn_player", pinfo)
	
	# Try to locate the player actor
	var player_node = get_node(str(pinfo.net_id))
	if (!player_node):
		print("Cannoot remove invalid node from tree")
		return
	
	# Mark the node for deletion
	player_node.queue_free()


remote func sync_bots(bot_count):
	if (get_tree().is_network_server()):
		# Calculate the target amount of spawned bots
		bot_count = network.server_info.max_players - network.players.size()
		# Relay this to the connected players
		rpc("sync_bots", bot_count)
	
	if (gamestate.spawned_bots > bot_count):
		# We have more bots than the target count - must remove some
		while (gamestate.spawned_bots > bot_count):
			# Locate the bot's node
			var bnode = get_node(gamestate.bot_info[gamestate.spawned_bots].name)
			if (!bnode):
				print("Must remove bots from game but cannot find it's node")
				return
			# Mark it for removal
			bnode.queue_free()
			# And update the spawned bot count
			gamestate.spawned_bots -= 1
	
	elif (gamestate.spawned_bots < bot_count):
		# We have less bots than the target count - must add some
		# Since every single bot uses the exact same scene path we can cahce it's loaded scene here
		# otherwise, we would have to move the following code into the while loop and change the dictionary
		# key ID to point into the correct bot info. In this case we are pointing to the 1
		var bot_class = load(gamestate.bot_info[1].actor_path)
		
		while (gamestate.spawned_bots < bot_count):
			var nbot = bot_class.instance()
			nbot.set_name(gamestate.bot_info[gamestate.spawned_bots+1].name)
			add_child(nbot)
			gamestate.spawned_bots += 1

