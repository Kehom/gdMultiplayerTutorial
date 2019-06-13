# This source code is provided as reference/companion material for the Godot Multiplayer Setup tutorial
# that can be freely found at http://kehomsforge.com and should not be commercialized
# in any form. It should remain free!
#
# By Yuri Sarudiansky

extends Control

# Maximum number of chat lines within the box container
export(int) var max_chat_lines = 50


func _ready():
	network.connect("chat_message_received", self, "add_chat_line")


func add_chat_line(msg):
	if ($pnlChat/ChatLines.get_child_count() >= max_chat_lines):
		$pnlChat/ChatLines.get_child(0).queue_free()
	
	var chatline = Label.new()
	chatline.autowrap = true
	chatline.text = msg
	$pnlChat/ChatLines.add_child(chatline)


func _on_txtChatInput_text_entered(new_text):
	# Cleanup the text
	var m = new_text.strip_edges()
	# Local chat box without any formatting
	add_chat_line(m)
	
	# Check if whisper or broadcast
	if (m.begins_with("@")):
		var t = m.split(" ", true, 1)
		# It must be checked that we actually have a message after the name. For simplicity sake
		# ignoring this check for the tutorial
		var player_name = t[0].trim_prefix("@")
		var dest_id = network.get_player_id(player_name)
		
		if (dest_id == 0):
			# Unable to locate the destination player for whispering
			add_chat_line("ERROR: Cannot locate player " + player_name)
		else:
			# Player found. Remote call directly to that player
			network.rpc_id(dest_id, "send_message", get_tree().get_network_unique_id(), t[1], false)
	
	else:
		# Send cleaned message for broadcast
		if (get_tree().is_network_server()):
			network.send_message(1, m, true)
		else:
			network.rpc_id(1, "send_message", get_tree().get_network_unique_id(), m, true)
	
	# Cleanup the input box so new messages can be entered without having to delete the previous one
	$txtChatInput.text = ""


func _on_btShowChat_pressed():
	if ($pnlChat.is_visible_in_tree()):
		$pnlChat.hide()
		$btShowChat.release_focus()
	else:
		$pnlChat.show()
		$txtChatInput.grab_focus()


func _on_whisper(msg_prefix):
	$txtChatInput.text = msg_prefix
	$txtChatInput.grab_focus()
	$txtChatInput.caret_position = msg_prefix.length()


func _on_txtChatInput_focus_entered():
	# Disable player input
	gamestate.accept_player_input = false
	# And show the chat box
	$pnlChat.show()


func _on_txtChatInput_focus_exited():
	# Re-enable player input
	gamestate.accept_player_input = true

