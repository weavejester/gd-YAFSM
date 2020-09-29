tool
extends GraphEdit
const Transition = preload("../src/Transition.gd")
const State = preload("../src/State.gd")
const StateMachine = preload("../src/StateMachine.gd")
const CustomGraphNode = preload("GraphNode.tscn")
const EntryGraphNode = preload("EntryGraphNode.tscn")
const ExitGraphNode = preload("ExitGraphNode.tscn")

const DEFAULT_NODE_NAME = "State"
const DEFAULT_NODE_OFFSET = Vector2.ZERO

onready var ContextMenu = $ContextMenu
onready var OverlayLog = $Overlay/Log

var focused_object setget set_focused_object
var focused_state_machine setget set_focused_state_machine

var selected_nodes = {}


func _init():
	add_valid_connection_type(0, 1)
	add_valid_connection_type(1, 0)
	add_valid_left_disconnect_type(1)
	add_valid_right_disconnect_type(0)

func _ready():
	connect("connection_request", self, "_on_connection_request")
	connect("disconnection_request", self, "_on_disconnection_request")
	connect("popup_request", self, "_on_popup_request")
	connect("delete_nodes_request", self, "_on_delete_nodes_request")
	connect("node_selected", self, "_on_node_selected")
	connect("node_unselected", self, "_on_node_unselected")
	ContextMenu.connect("index_pressed", self, "_on_ContextMenu_index_pressed")

func _on_connection_request(from, from_slot, to, to_slot):
	connect_state_node(from, from_slot, to, to_slot)

func _on_disconnection_request(from, from_slot, to, to_slot):
	disconnect_state_node(from, from_slot, to, to_slot)

# Always called after connect_node() to update data of focused_state_machine
func _on_connect_node(from, from_slot, to, to_slot):
	var state = focused_state_machine.states.get(from)
	if state:
		if to in state.transitions: # Transition existed, mainly to silent warning from State.add_transition
			return

	var new_transition = Transition.new()
	new_transition.from = from
	new_transition.to = to
	if not state:
		state = State.new(from)
		focused_state_machine.add_state(state)
	state.add_transition(new_transition)

# Always called after disconnect_node() to update data of focused_state_machine
func _on_disconnect_node(from, from_slot, to, to_slot):
	var state = focused_state_machine.states.get(from)
	if state:
		state.remove_transition(to)

func _on_delete_nodes_request():
	for node in selected_nodes.values():
		remove_node_connections(node.name)
		remove_child(node)
		focused_state_machine.remove_state(node.name)
	selected_nodes.clear()
	check_entry_node()

func _on_node_selected(node):
	selected_nodes[node.name] = node

func _on_node_unselected(node):
	selected_nodes.erase(node.name)

func _on_node_name_changed(old, new):
	focused_state_machine.change_state_name(old, new)
	# Manually handle re-connections after rename
	for connection in get_connection_list():
		if connection.from == old:
			disconnect_state_node(connection.from, connection.from_port, connection.to, connection.to_port)
			connect_state_node(new, connection.from_port, connection.to, connection.to_port)
		elif connection.to == old:
			disconnect_state_node(connection.from, connection.from_port, connection.to, connection.to_port)
			connect_state_node(connection.from, connection.from_port, new, connection.to_port)

func _on_popup_request(position):
	ContextMenu.rect_position = get_viewport().get_mouse_position()
	ContextMenu.popup()

func _on_ContextMenu_index_pressed(index):
	var local_mouse_pos = get_local_mouse_position() + scroll_offset
	match index: # TODO: Proper way to handle menu items
		0: # Add State
			var node = CustomGraphNode.instance()
			add_node(node, DEFAULT_NODE_NAME, local_mouse_pos)
		1: # Add Entry
			if State.ENTRY_KEY in focused_state_machine.states:
				push_warning("Entry node already exist")
				return
			var node = EntryGraphNode.instance()
			add_node(node, State.ENTRY_KEY, local_mouse_pos)
			OverlayLog.text = ""
		2: # Add Exit
			if State.EXIT_KEY in focused_state_machine.states:
				push_warning("Exit node already exist")
				return
			var node = ExitGraphNode.instance()
			add_node(node, State.EXIT_KEY, local_mouse_pos)

func _on_new_node_added(node, node_name=DEFAULT_NODE_NAME, offset=DEFAULT_NODE_OFFSET):
	if node.has_signal("name_changed"): # BaseGraphNode doesn't have name_changed signal
		node.connect("name_changed", self, "_on_node_name_changed")
	node.offset = offset
	node.name = node_name
	node.state.name = node.name
	focused_state_machine.add_state(node.state)

func _on_focused_object_changed(new_obj):
	if new_obj == null:
		set_focused_object(null)
	if new_obj is StateMachine:
		set_focused_state_machine(new_obj)

func _on_focused_state_machine_changed(new_state_machine):
	if new_state_machine:
		clear_graph()
		draw_graph()
		check_entry_node()
	else:
		clear_graph()

func connect_state_node(from, from_slot, to, to_slot):
	connect_node(from, from_slot, to, to_slot)
	_on_connect_node(from, from_slot, to, to_slot)

func disconnect_state_node(from, from_slot, to, to_slot):
	disconnect_node(from, from_slot, to, to_slot)
	_on_disconnect_node(from, from_slot, to, to_slot)

func draw_graph():
	for state_key in focused_state_machine.states.keys():
		var is_entry = state_key == State.ENTRY_KEY
		var is_exit = state_key == State.EXIT_KEY
		var state = focused_state_machine.states[state_key]
		var new_node
		if is_entry:
			new_node = EntryGraphNode.instance()
		elif is_exit:
			new_node = ExitGraphNode.instance()
		else:
			new_node = CustomGraphNode.instance()

		new_node.state = state
		add_node(new_node, state_key, state.offset)
		for transition in state.transitions.values():
			# Reflecting state node, so call connect_node instead
			connect_node(transition.from, 0, transition.to, 0) # TODO: Save port index to state
			new_node._on_state_transition_added(transition)

func clear_graph():
	clear_connections()
	for child in get_children():
		if child is GraphNode:
			remove_child(child)
			child.queue_free()

func add_node(node, node_name=DEFAULT_NODE_NAME, offset=Vector2.ZERO):
	add_child(node)
	_on_new_node_added(node, node_name, offset)

func remove_node_connections(node_name):
	for connection in get_connection_list():
		if connection.from == node_name or connection.to == node_name:
			disconnect_state_node(connection.from, connection.from_port, connection.to, connection.to_port)

func check_entry_node():
	if focused_state_machine:
		if not focused_state_machine.has_entry():
			OverlayLog.text = "Warning: Entry node is required, right-click on graph and select Add Entry"

func set_focused_object(obj):
	if focused_object != obj:
		focused_object = obj
		_on_focused_object_changed(obj)

func set_focused_state_machine(state_machine):
	if focused_state_machine != state_machine:
		focused_state_machine = state_machine
		_on_focused_state_machine_changed(state_machine)