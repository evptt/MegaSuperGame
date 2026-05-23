extends Node
class_name CheckpointProgress

var expected_checkpoint_index: int = 1


func reset() -> void:
	expected_checkpoint_index = 1


func can_trigger(checkpoint_index: int) -> bool:
	return checkpoint_index == expected_checkpoint_index


func advance() -> void:
	expected_checkpoint_index += 1