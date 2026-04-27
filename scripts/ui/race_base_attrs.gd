class_name RaceBaseAttrs
extends RefCounted

## Static table of race base attributes (INT/CON/AGI/STR/MAG_RES/PHYS_RES),
## mirrored from the server's `Game::DiceRoller.base_for(race)`. Hardcoded
## here because the CHARACTER_LIST_RESPONSE shape currently doesn't ship
## base_attrs / dice_roll per existing character — only the FIFA-style
## "available throws" for a NEW character. Once the server starts shipping
## those on `Character#to_summary`, prefer the wire data over this table
## and delete it.
##
## Source: argentum-united-server CLAUDE.md, Race attribute scale section.
## STEP=16, base values 12-92, dice +0 to +7, max 99. Note enano's MAG_RES
## of 44 is intentional — the dwarf is durable in body but not warded,
## per the server's canonical table.

const TABLE := {
	"gnomo":  {"int": 92, "con": 12, "agi": 92, "str": 12, "mag_res": 92, "phys_res": 12},
	"elfo":   {"int": 76, "con": 28, "agi": 76, "str": 28, "mag_res": 76, "phys_res": 28},
	"humano": {"int": 50, "con": 50, "agi": 50, "str": 50, "mag_res": 50, "phys_res": 50},
	"enano":  {"int": 28, "con": 76, "agi": 28, "str": 76, "mag_res": 44, "phys_res": 76},
	"orco":   {"int": 12, "con": 92, "agi": 12, "str": 92, "mag_res": 12, "phys_res": 92},
}

# Fallback used when the server hands us a race we don't know (e.g. elfo_oscuro
# from CLAUDE.md, which isn't in the server's RACES list as of 2026-04-25).
# Even split keeps the card readable.
const FALLBACK := {"int": 50, "con": 50, "agi": 50, "str": 50, "mag_res": 50, "phys_res": 50}

# Canonical attribute key order. Card and tests reference this so adding a
# seventh attr later is a one-line change.
const ATTR_KEYS := ["int", "con", "agi", "str", "mag_res", "phys_res"]


static func for_race(race: String) -> Dictionary:
	return TABLE.get(race, FALLBACK).duplicate()


# FIFA "OVR"-like rating. Floor of the mean across all six attrs (was four
# before the resistances were exposed on the card). Lifted into a static
# helper so a unit test can pin the formula without reaching into the card UI.
static func rating(attrs: Dictionary) -> int:
	var sum_attrs: int = 0
	for key in ATTR_KEYS:
		sum_attrs += int(attrs.get(key, 0))
	return int(floor(sum_attrs / float(ATTR_KEYS.size())))


# Combine race base + dice bonus into the effective attrs used for the rating.
# Both inputs are Dictionary keyed on ATTR_KEYS. Dice currently only lands
# on the four primary attrs (server hands no resistance dice yet) but we
# fold in any keys the server does send, future-proofing for free.
static func combine(base: Dictionary, dice: Dictionary) -> Dictionary:
	var out := {}
	for key in ATTR_KEYS:
		out[key] = int(base.get(key, 0)) + int(dice.get(key, 0))
	return out
