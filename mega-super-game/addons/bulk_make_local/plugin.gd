@tool
extends EditorPlugin

var editor_selection: EditorSelection
var scene_tree: Tree
var should_check_for_menu = false

func _enter_tree():
    editor_selection = get_editor_interface().get_selection()
    call_deferred("_find_and_hook_scene_tree")

func _find_and_hook_scene_tree():
    await get_tree().create_timer(0.5).timeout
    
    var base = get_editor_interface().get_base_control()
    scene_tree = _find_tree_in_editor(base)
    
    if scene_tree:
        print("Bulk Make Local: Context menu integration active!")
        get_tree().process_frame.connect(_check_for_context_menu)

func _find_tree_in_editor(node: Node) -> Tree:
    if node is Tree:
        var parent = node.get_parent()
        if parent and ("Scene" in parent.name or parent.get_class() == "SceneTreeDock"):
            return node
    
    for child in node.get_children():
        var found = _find_tree_in_editor(child)
        if found:
            return found
    return null

func _check_for_context_menu():
    var selected = editor_selection.get_selected_nodes()
    if selected.size() <= 1:
        return
    
    var base = get_editor_interface().get_base_control()
    var menu = _find_visible_popup(base)
    
    if menu and not should_check_for_menu:
        should_check_for_menu = true
        _extend_context_menu(menu)
        await get_tree().create_timer(0.3).timeout
        should_check_for_menu = false

func _find_visible_popup(node: Node) -> PopupMenu:
    if node is PopupMenu and node.visible:
        if node.get_item_count() > 0:
            return node
    
    for child in node.get_children():
        var found = _find_visible_popup(child)
        if found:
            return found
    
    return null

func _extend_context_menu(menu: PopupMenu):
    for i in range(menu.get_item_count()):
        if menu.get_item_id(i) == 9001:
            return
    
    menu.add_separator()
    menu.add_item("--- Bulk Make Local ---", 9000)
    menu.set_item_disabled(menu.get_item_count() - 1, true)
    menu.add_item("Make Selected Local", 9001)
    menu.add_item("Make Selected + Children", 9002)
    menu.add_separator()
    menu.add_item("Make ALL Local", 9003)
    
    if not menu.id_pressed.is_connected(_on_context_menu_item):
        menu.id_pressed.connect(_on_context_menu_item)

func _on_context_menu_item(id: int):
    match id:
        9001:
            make_selected_local(false)
        9002:
            make_selected_local(true)
        9003:
            _on_make_all_pressed()

func _exit_tree():
    if get_tree() and get_tree().process_frame.is_connected(_check_for_context_menu):
        get_tree().process_frame.disconnect(_check_for_context_menu)

func _on_make_all_pressed():
    var confirmation = AcceptDialog.new()
    confirmation.dialog_text = "Do you really want to make ALL scene instances in this scene local?\n\nThis cannot be undone!"
    confirmation.title = "Make all instances local?"
    confirmation.ok_button_text = "Yes, make all local"
    confirmation.confirmed.connect(make_all_instances_local)
    
    confirmation.add_cancel_button("Cancel")
    
    get_editor_interface().get_base_control().add_child(confirmation)
    confirmation.popup_centered()
    confirmation.confirmed.connect(confirmation.queue_free)
    confirmation.canceled.connect(confirmation.queue_free)

func make_selected_local(include_children: bool):
    var selected_nodes = editor_selection.get_selected_nodes()
    
    if selected_nodes.is_empty():
        printerr("No nodes selected!")
        return
    
    var undo_redo = get_undo_redo()
    undo_redo.create_action("Bulk Make Local")
    
    var count = 0
    for node in selected_nodes:
        if include_children:
            count += _make_local_recursive(node, undo_redo)
        else:
            if _is_scene_instance(node):
                _make_node_local(node, undo_redo)
                count += 1
    
    undo_redo.commit_action()
    
    if count > 0:
        print("%d scenes made local" % count)
    else:
        print("No scene instances in selection")

func make_all_instances_local():
    var edited_scene = get_editor_interface().get_edited_scene_root()
    
    if not edited_scene:
        printerr("No scene opened!")
        return
    
    var undo_redo = get_undo_redo()
    undo_redo.create_action("Make All Instances Local")
    
    var count = _make_local_recursive(edited_scene, undo_redo)
    
    undo_redo.commit_action()
    
    if count > 0:
        print("All %d scene instances made local" % count)
    else:
        print("No scene instances in scene")

func _make_local_recursive(node: Node, undo_redo: EditorUndoRedoManager) -> int:
    var count = 0
    
    if _is_scene_instance(node):
        _make_node_local(node, undo_redo)
        count += 1
    
    for child in node.get_children():
        count += _make_local_recursive(child, undo_redo)
    
    return count

func _is_scene_instance(node: Node) -> bool:
    return node.scene_file_path != ""

func _make_node_local(node: Node, undo_redo: EditorUndoRedoManager):
    var owner_node = node.owner
    var scene_path = node.scene_file_path
    
    undo_redo.add_do_method(node, "set_scene_file_path", "")
    undo_redo.add_undo_method(node, "set_scene_file_path", scene_path)
    
    _set_owner_recursive(node, owner_node, undo_redo)

func _set_owner_recursive(node: Node, new_owner: Node, undo_redo: EditorUndoRedoManager):
    for child in node.get_children():
        if child.owner != new_owner:
            var old_owner = child.owner
            undo_redo.add_do_property(child, "owner", new_owner)
            undo_redo.add_undo_property(child, "owner", old_owner)
        _set_owner_recursive(child, new_owner, undo_redo)
