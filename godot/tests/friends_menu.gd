extends SceneTree
## Friends list screen, room invites from the lobby and the invite banner.
## No server needed: Net.friends_data and signals are fed directly.
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _run() -> void:
	var net: Node = root.get_node("Net")
	var saved_token: String = net.get("session_token")
	var saved_profile: Dictionary = net.get("profile")
	net.set("session_token", "test-token")
	net.set("profile", {"name": "Lider", "rank": "Recruta", "xp": 0})
	net.set("_friends_timer", 999.0) # no real polling during the test
	net.set("friends_data", {"requests": ["Caio"], "friends": [
		{"name": "Ana", "rank": "Cabo", "online": true, "status": "room", "code": "ABCDE"},
		{"name": "Beto", "rank": "Recruta", "online": true, "status": "menu", "code": ""},
		{"name": "Duda", "rank": "Recruta", "online": false, "status": "offline", "code": ""}]})
	var menu = load("res://scenes/menu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	await process_frame
	menu.call("_show_main")
	await process_frame
	var friends_button := menu.find_child("FriendsButton", true, false) as Button
	_check(friends_button != null and friends_button.text.contains("1 pedido"), "Main menu shows Amigos with pending requests")
	var ladder := menu.find_child("RankLadder", true, false) as RichTextLabel
	_check(ladder != null and ladder.text.contains("Marechal 70000") and ladder.text.contains("[b]Recruta 0[/b]"), "Main menu lists every rank, current one highlighted")
	menu.call("_show_friends")
	net.set("_friends_timer", 999.0)
	await process_frame
	_check(menu.find_child("FriendNameField", true, false) != null and menu.find_child("AddFriendButton", true, false) != null, "Add friend by name")
	_check(menu.find_child("Request_accept_Caio", true, false) != null, "Pending request can be accepted")
	_check(menu.find_child("JoinFriend_Ana", true, false) != null, "Friend in a room can be joined")
	_check(menu.find_child("JoinFriend_Beto", true, false) == null, "Friend in the menu has no room to join")
	_check(menu.find_child("RemoveFriend_Duda", true, false) != null, "Friends can be removed")
	# In a team room: online friends not in this room can be invited.
	net.set("my_id", "me")
	net.set("party_code", "K7Q2M")
	menu.call("_on_party_updated", {"t": "party", "party": true, "code": "K7Q2M", "leader": "me", "size": 2, "bots": true, "teams": ["Alfa", "Bravo"], "allReady": true,
		"players": [{"id": "me", "name": "Lider", "rank": "Recruta", "team": 0, "ready": true}]})
	await process_frame
	_check(menu.find_child("Invite_Ana", true, false) != null, "Invite friend who is in another room")
	_check(menu.find_child("Invite_Beto", true, false) != null, "Invite friend who is online in the menu")
	_check(menu.find_child("Invite_Duda", true, false) == null, "Offline friends cannot be invited")
	# Professional panel: card, every friend as a row (offline dimmed, last), online count, add-by-name.
	_check(menu.find_child("InviteFriendsCard", true, false) != null, "Invite panel card in the room")
	var list := menu.find_child("InviteFriendsList", true, false) as VBoxContainer
	var order: Array[String] = []
	if list != null:
		for child in list.get_children():
			order.append(str(child.name).trim_prefix("InviteRow_"))
	_check(order == ["Beto", "Ana", "Duda"], "Free online friends first, offline last: %s" % [order])
	var count: Node = menu.find_child("InviteOnlineCount", true, false)
	_check(count != null and count.get_child_count() == 1, "Online count shown")
	_check(menu.find_child("InviteAddField", true, false) != null and menu.find_child("InviteAddButton", true, false) != null, "Add friend without leaving the room")
	var search := menu.find_child("InviteSearch", true, false) as LineEdit
	_check(search != null and not search.visible, "Search hidden for a short list")
	# Friends refresh while in the room: only the list is rebuilt (screen does not flash).
	var card_before: Node = menu.find_child("InviteFriendsCard", true, false)
	net.emit_signal("friends_updated", net.get("friends_data"))
	await process_frame
	_check(menu.find_child("InviteFriendsCard", true, false) == card_before, "Friends refresh keeps the room screen")
	# Receiving an invite shows the card with who invited and the room.
	net.emit_signal("friend_invite", "Ana", "ABCDE")
	await process_frame
	var banner := menu.find_child("InviteBanner", true, false) as Control
	_check(banner != null and banner.visible, "Invite banner appears")
	var invite_text := menu.find_child("InviteText", true, false) as Label
	_check(invite_text != null and invite_text.text.contains("Ana"), "Invite card names who invited")
	_check(menu.find_child("InviteTimer", true, false) != null, "Invite card shows the time left")
	_check(menu.find_child("AcceptInviteButton", true, false) != null, "Invite can be accepted")
	(menu.find_child("IgnoreInviteButton", true, false) as Button).pressed.emit()
	_check(not banner.visible and (net.get("pending_invite") as Dictionary).is_empty(), "Invite can be ignored")
	menu.queue_free()
	await process_frame
	net.set("party_code", "")
	net.set("my_id", "")
	net.set("friends_data", {})
	net.set("session_token", saved_token)
	net.set("profile", saved_profile)
	for failure in failures:
		printerr(failure)
	print("FRIENDS MENU: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
