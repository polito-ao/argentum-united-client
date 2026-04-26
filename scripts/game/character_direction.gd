class_name CharacterDirection extends RefCounted
## Pure helpers for translating movement deltas + headings into the
## animation names exposed by SpriteFrames built by SpriteFramesBuilder.
## Stateless — every method is static and side-effect-free, so it's
## trivially unit-testable.

const NORTH := "north"
const SOUTH := "south"
const EAST := "east"
const WEST := "west"

const ANIM_PREFIX := "walk_"


static func from_delta(dx: int, dy: int) -> String:
	# Pick the dominant axis. AO-style movement is strictly cardinal — exactly
	# one of dx/dy is non-zero per step — but break ties horizontally just in
	# case the server ever ships a diagonal correction.
	if dx == 0 and dy == 0:
		return SOUTH
	if abs(dx) >= abs(dy):
		return EAST if dx > 0 else WEST
	return SOUTH if dy > 0 else NORTH


static func anim(direction: String) -> String:
	return ANIM_PREFIX + direction
