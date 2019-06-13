# This source code is provided as reference/companion material for the Godot Multiplayer Setup tutorial
# that can be freely found at http://kehomsforge.com and should not be commercialized
# in any form. It should remain free!
#
# By Yuri Sarudiansky

extends MenuButton

signal whisper_clicked(msg_prefix)                 # Given when the whisper option in the pop menu is clicked

# Popup menu entry IDs
enum PopID { whisper = 1, kick, ban }

# Network ID of the player associated with this object
var net_id = 0

func _ready():
	var pop = get_popup()        # Just a shortcut
	pop.add_item("Whisper", PopID.whisper)
	if (get_tree().is_network_server()):
		pop.add_separator()
		pop.add_item("Kick", PopID.kick)
		pop.add_item("Ban", PopID.ban)
	
	pop.connect("id_pressed", self, "_on_popup_id_pressed")


func set_info(pname, pcolor):
	$PlayerRow/lblName.text = pname
	$PlayerRow/Icon.modulate = pcolor


func set_latency(v):
	$PlayerRow/lblLatency.text = "(" + str(int(v)) + ")"


func _on_popup_id_pressed(id):
	match id:
		PopID.whisper:
			emit_signal("whisper_clicked", "@" + network.players[net_id].name + " ")
		
		PopID.kick:
			$pnlKickBan/btKickBan.text = "Kick"
			$pnlKickBan.show()
			$pnlKickBan/txtReason.grab_focus()
		
		PopID.ban:
			$pnlKickBan/btKickBan.text = "Ban"
			$pnlKickBan.show()
			$pnlKickBan/txtReason.grab_focus()


func _on_btCancel_pressed():
	$pnlKickBan.hide()


func _on_btKickBan_pressed():
	var reason = $pnlKickBan/txtReason.text
	if (reason.empty()):
		reason = "No reason"
	if ($pnlKickBan/btKickBan.text == "Kick"):
		print("Kicking player with unique ID ", net_id)
		network.kick_player(net_id, reason)
	else:
		print("Banning not implemented yet")
	
	$pnlKickBan.hide()

