extends Node

const CUTSCENE_VIDEO_PATH := "res://assets/sounds/cutscene.ogv"
const DOUBLE_PRESS_THRESHOLD := 0.35

var _pending_cutscene := false
var _cutscene_active := false
var _skip_timer := 0.0
var _space_press_count := 0
var _global_audio_backup := {}

func _ready() -> void:
    # no global pause_mode set here to avoid engine compatibility issues
    set_process(true)
    set_process_input(true)
    set_process_unhandled_input(true)
    get_tree().connect("scene_changed", Callable(self , "_on_current_scene_changed"))

func request_cutscene() -> void:
    _pending_cutscene = true
    _cutscene_active = false
    _skip_timer = 0.0
    _space_press_count = 0

func cancel_cutscene_request() -> void:
    _pending_cutscene = false
    _cutscene_active = false
    _skip_timer = 0.0
    _space_press_count = 0

func _on_current_scene_changed() -> void:
    if not _pending_cutscene:
        return
    _pending_cutscene = false
    _show_cutscene_overlay()

func _show_cutscene_overlay() -> void:
    var scene_root := get_tree().current_scene
    if scene_root == null:
        return
    var overlay := CanvasLayer.new()
    overlay.name = "CutsceneOverlay"
    overlay.layer = 2000
    overlay.process_mode = Node.PROCESS_MODE_ALWAYS
    overlay.set_process(true)

    var overlay_root := Control.new()
    overlay_root.name = "CutsceneOverlayRoot"
    overlay_root.set_anchors_preset(Control.PRESET_FULL_RECT)
    overlay_root.mouse_filter = Control.MOUSE_FILTER_STOP
    overlay_root.set_process_input(true)
    overlay_root.set_process_unhandled_input(true)
    overlay_root.set_process(true)
    overlay.add_child(overlay_root)

    var dim := ColorRect.new()
    dim.set_anchors_preset(Control.PRESET_FULL_RECT)
    dim.color = Color(0.0, 0.0, 0.0, 0.72)
    overlay_root.add_child(dim)

    var video_scene := load("res://scenes/ui/cutscene_video.tscn") as PackedScene
    if video_scene == null:
        _end_cutscene(overlay)
        return

    var video_player := video_scene.instantiate()
    video_player.name = "CutsceneVideo"
    video_player.set("stream", load(CUTSCENE_VIDEO_PATH))
    video_player.set_anchors_preset(Control.PRESET_FULL_RECT)
    overlay_root.add_child(video_player)

    var hint := Label.new()
    hint.name = "CutsceneHint"
    hint.text = "Двойное нажатие пробела для пропуска"
    hint.add_theme_font_size_override("font_size", 18)
    hint.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.88))
    hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
    hint.custom_minimum_size = Vector2(0.0, 48.0)
    overlay_root.add_child(hint)

    scene_root.add_child(overlay)
    # grab focus only after overlay is in scene tree
    overlay_root.grab_focus()
    _freeze_game()
    _cutscene_active = true
    _mute_global_audio()

    if video_player.stream != null:
        video_player.finished.connect(Callable(self , "_on_video_finished"))
        video_player.play()
    else:
        _end_cutscene(overlay)

func _process(delta: float) -> void:
    if not _cutscene_active:
        return
    if _space_press_count > 0:
        _skip_timer += delta
        if _skip_timer > DOUBLE_PRESS_THRESHOLD:
            _skip_timer = 0.0
            _space_press_count = 0

func _input(event: InputEvent) -> void:
    if not _cutscene_active:
        return
    if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
        if _skip_timer <= DOUBLE_PRESS_THRESHOLD and _space_press_count > 0:
            _space_press_count += 1
        else:
            _space_press_count = 1
        _skip_timer = 0.0
        if _space_press_count >= 2:
            var overlay := get_tree().current_scene.get_node_or_null("CutsceneOverlay")
            _end_cutscene(overlay)

    if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_ESCAPE or event.is_action_pressed("ui_cancel")):
        get_viewport().set_input_as_handled()

func _on_video_finished() -> void:
    var overlay := get_tree().current_scene.get_node_or_null("CutsceneOverlay")
    _end_cutscene(overlay)

func _end_cutscene(overlay: Node) -> void:
    if overlay != null and overlay.is_inside_tree():
        overlay.queue_free()
    _unfreeze_game()
    _restore_global_audio()
    _cutscene_active = false
    _skip_timer = 0.0
    _space_press_count = 0


func _freeze_game() -> void:
    var players := get_tree().get_nodes_in_group("player")
    for p in players:
        if p is Node:
            p.set_process(false)
            p.set_physics_process(false)
            p.set_process_input(false)

func _unfreeze_game() -> void:
    var players := get_tree().get_nodes_in_group("player")
    for p in players:
        if p is Node:
            p.set_process(true)
            p.set_physics_process(true)
            p.set_process_input(true)


func _mute_global_audio() -> void:
    _global_audio_backup.clear()
    var ga := get_tree().get_current_scene().get_node_or_null("GlobalAudio")
    if ga == null:
        return
    var ambient := ga.get_node_or_null("AmbientPlayer") as AudioStreamPlayer
    var breathing := ga.get_node_or_null("BreathingPlayer") as AudioStreamPlayer
    if ambient != null:
        _global_audio_backup["ambient_playing"] = ambient.playing
        _global_audio_backup["ambient_volume_db"] = ambient.volume_db
        ambient.stop()
    if breathing != null:
        _global_audio_backup["breathing_playing"] = breathing.playing
        _global_audio_backup["breathing_volume_db"] = breathing.volume_db
        breathing.stop()

func _restore_global_audio() -> void:
    var ga := get_tree().get_current_scene().get_node_or_null("GlobalAudio")
    if ga == null:
        return
    var ambient := ga.get_node_or_null("AmbientPlayer") as AudioStreamPlayer
    var breathing := ga.get_node_or_null("BreathingPlayer") as AudioStreamPlayer
    if ambient != null and _global_audio_backup.has("ambient_playing"):
        ambient.volume_db = _global_audio_backup.get("ambient_volume_db", ambient.volume_db)
        if _global_audio_backup.get("ambient_playing", false) and ambient.stream != null:
            ambient.play()
    if breathing != null and _global_audio_backup.has("breathing_playing"):
        breathing.volume_db = _global_audio_backup.get("breathing_volume_db", breathing.volume_db)
        if _global_audio_backup.get("breathing_playing", false) and breathing.stream != null:
            breathing.play()
