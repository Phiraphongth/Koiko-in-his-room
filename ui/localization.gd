class_name Localization
extends RefCounted
## Helper around Godot's TranslationServer for text that is set from code.
##
## Text written in a .tscn (Button.text, Label.text) is translated by Godot
## automatically and re-translated when the locale changes. Text assigned at
## runtime is not, so bind it here instead:
##
##   Localization.set_text(label, &"HUD_OBJECTIVE_FIND_KEYCARDS", [found, total])
##
## SettingsManager calls refresh() after a language switch, which re-applies
## every bound node. Keys and translations live in localization/*.csv.

const GROUP := &"localized"
const KEY_META := &"loc_key"
const ARGS_META := &"loc_args"


## tr() with optional %-formatting: t(&"KEYCARDS_FOUND", [2, 3])
static func t(key: StringName, args: Array = []) -> String:
	# CSV cells keep line breaks as a literal backslash-n so rows stay on one line.
	var text := TranslationServer.translate(key).replace("\\n", "\n")
	return text % args if not args.is_empty() else text


## Same as t(), but in one fixed language whatever the player has selected.
## The announcer uses this so the PA voice always speaks English while the
## banner on screen follows the player's language.
static func t_in(locale: String, key: StringName, args: Array = []) -> String:
	var translation := TranslationServer.get_translation_object(locale)
	var text := String(translation.get_message(key)) if translation else ""
	if text.is_empty():
		return t(key, args) # not a key, or that language has no entry for it
	text = text.replace("\\n", "\n")
	return text % args if not args.is_empty() else text


## True when this string is a known translation key (used by the HUD to decide
## whether incoming text should be bound for live language switching).
static func is_key(text: String) -> bool:
	return text != "" and TranslationServer.translate(text) != text


## Assigns translated text now and re-applies it on every language change.
## Works with any node that has a `text` property (Label, Button, Label3D...).
static func set_text(node: Node, key: StringName, args: Array = []) -> void:
	node.set_meta(KEY_META, key)
	node.set_meta(ARGS_META, args)
	if not node.is_in_group(GROUP):
		node.add_to_group(GROUP)
	apply(node)


## Drops the binding (for nodes that switch to untranslated text).
static func clear(node: Node) -> void:
	node.remove_meta(KEY_META)
	node.remove_from_group(GROUP)


static func apply(node: Node) -> void:
	if node.has_meta(KEY_META):
		node.set(&"text", t(node.get_meta(KEY_META), node.get_meta(ARGS_META, [])))


## Re-applies every bound node in the tree; also refreshes .tscn-authored text.
static func refresh(tree: SceneTree) -> void:
	if tree == null:
		return
	for node in tree.get_nodes_in_group(GROUP):
		apply(node)
	_notify_translation_changed(tree.root)


static func _notify_translation_changed(node: Node) -> void:
	node.notification(Node.NOTIFICATION_TRANSLATION_CHANGED)
	for child in node.get_children():
		_notify_translation_changed(child)
