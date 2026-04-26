class_name RaceBaseAttrs
extends RefCounted

## Static table of race base attributes (INT/CON/AGI/STR), mirrored from the
## server's `Game::DiceRoller.base_for(race)`. Hardcoded here because the
## CHARACTER_LIST_RESPONSE shape currently doesn't ship base_attrs / dice_roll
## per existing character — only the FIFA-style "available throws" for a NEW
## character. Once the server starts shipping those on `Character#to_summary`,
## prefer the wire data over this table and delete it.
##
## Source: argentum-united-server CLAUDE.md, Race attribute scale section.
## STEP=16, base values 12-92, dice +0 to +7, max 99.

const TABLE := {
	"gnomo":  {"int": 92, "con": 12, "agi": 92, "str": 12},
	"elfo":   {"int": 76, "con": 28, "agi": 76, "str": 28},
	"humano": {"int": 50, "con": 50, "agi": 50, "str": 50},
	"enano":  {"int": 28, "con": 76, "agi": 28, "str": 76},
	"orco":   {"int": 12, "con": 92, "agi": 12, "str": 92},
}

# Fallback used when the server hands us a race we don't know (e.g. elfo_oscuro
# from CLAUDE.md, which isn't in the server's RACES list as of 2026-04-25).
# Even split keeps the card readable.
const FALLBACK := {"int": 50, "con": 50, "agi": 50, "str": 50}


static func for_race(race: String) -> Dictionary:
	return TABLE.get(race, FALLBACK).duplicate()


# FIFA "OVR"-like rating. Floor of (INT+CON+AGI+STR)/4. Lifted into a static
# helper so a unit test can pin the formula without reaching into the card UI.
static func rating(attrs: Dictionary) -> int:
	var sum_attrs: int = (
		int(attrs.get("int", 0))
		+ int(attrs.get("con", 0))
		+ int(attrs.get("agi", 0))
		+ int(attrs.get("str", 0))
	)
	return int(floor(sum_attrs / 4.0))


# Combine race base + dice bonus into the effective attrs used for the rating.
# Both inputs are Dictionary { "int": Int, "con": Int, "agi": Int, "str": Int }.
static func combine(base: Dictionary, dice: Dictionary) -> Dictionary:
	return {
		"int": int(base.get("int", 0)) + int(dice.get("int", 0)),
		"con": int(base.get("con", 0)) + int(dice.get("con", 0)),
		"agi": int(base.get("agi", 0)) + int(dice.get("agi", 0)),
		"str": int(base.get("str", 0)) + int(dice.get("str", 0)),
	}
