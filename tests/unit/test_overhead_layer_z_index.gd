extends GutTest
## Tests the z-stack contract that gives the player AO-style "walk behind
## trees" occlusion: map layer 4 (the Cucsi "above-player" layer — trees,
## roof corners, hanging signs) must render IN FRONT of the player and
## NPCs. Concretely the world scene must expose:
##
##   $Ground   (map layers 1-3)        z = 0
##   $Overhead (map layer 4)           z > player z
##   $PlayerSprite                     z < overhead z
##   $Entities (NPCs + other players)  z < overhead z
##
## The test instantiates the world scene and inspects z_index values
## directly. Black-box — does not depend on `_render_ground` having run,
## so it doesn't need a server / map JSON / texture cache.

const WorldScene = preload("res://scenes/world/world.tscn")


func _build_world() -> Node:
	# Instantiate via `instantiate()` rather than `_ready()`-ing into the
	# tree: world.gd's _ready needs HUD widgets that only resolve once
	# we're under a SceneTree, but z_index is set declaratively in the
	# .tscn so it's already populated on the bare instance.
	var world := WorldScene.instantiate()
	# Don't add to the tree — we don't want _ready / setup to fire and
	# start hitting the network or autoloads. queue_free in cleanup.
	return world


func after_each():
	# Free any leftover instances from the test (tests build their own).
	pass


func test_overhead_node_exists():
	var world = _build_world()
	assert_not_null(world.get_node_or_null("Overhead"),
		"world.tscn must expose an Overhead Node2D for layer-4 rendering")
	world.free()


func test_overhead_z_above_player_sprite():
	var world = _build_world()
	var overhead: Node2D = world.get_node("Overhead")
	var player: Node2D = world.get_node("PlayerSprite")
	assert_gt(overhead.z_index, player.z_index,
		"Overhead must render above PlayerSprite so the player walks BEHIND trees")
	world.free()


func test_overhead_z_above_entities():
	# Entities = NPCs + other players. Same occlusion contract applies.
	var world = _build_world()
	var overhead: Node2D = world.get_node("Overhead")
	var entities: Node2D = world.get_node("Entities")
	assert_gt(overhead.z_index, entities.z_index,
		"Overhead must render above Entities (NPCs + other players)")
	world.free()


func test_ground_z_below_player_sprite():
	# Ground = map layers 1-3 (floor + walkables). Must render UNDER the
	# player so the player visibly stands on the floor.
	var world = _build_world()
	var ground: Node2D = world.get_node("Ground")
	var player: Node2D = world.get_node("PlayerSprite")
	assert_lt(ground.z_index, player.z_index,
		"Ground must render below PlayerSprite — the player stands on tiles, not under them")
	world.free()


func test_ground_items_and_chests_between_ground_and_player():
	# Dropped items / chests sit on the floor, in front of tiles but
	# behind the player. Captures the documented z-stack ordering.
	var world = _build_world()
	var ground: Node2D = world.get_node("Ground")
	var ground_items: Node2D = world.get_node("GroundItems")
	var chests: Node2D = world.get_node("Chests")
	var player: Node2D = world.get_node("PlayerSprite")
	assert_gt(ground_items.z_index, ground.z_index, "GroundItems above Ground")
	assert_lt(ground_items.z_index, player.z_index, "GroundItems below PlayerSprite")
	assert_gt(chests.z_index, ground_items.z_index, "Chests above GroundItems")
	assert_lt(chests.z_index, player.z_index, "Chests below PlayerSprite")
	world.free()
