class_name ClassRaceHints
extends RefCounted

## One-line playstyle hints for the FIFA card on the character-select screen.
##
## The matrix is synthesized from class identity (Mago=carry caster, Bardo=
## evasive caster, Clerigo=hybrid healer, Paladin=melee+magic, Asesino=burst,
## Cazador=ranged phys, Guerrero=tank) and race base attrs (Gnomo=high
## INT/AGI/MagRes, Elfo=balanced caster, Humano=jack-of-all, Enano=durable
## melee, Orco=heavy hitter). Each hint is a punchy gameplay-oriented one-
## liner under 80 characters.
##
## Returns "" for unknown class+race. Callers should hide the hint label
## when the result is empty (e.g. before a class is picked).
##
## English copy is intentional even though "code in English, content in
## Spanish" is the project rule -- these are short UI hints; a localization
## pass can replace them in M3+.

const CLASS_SLUGS := ["mago", "bardo", "clerigo", "paladin", "asesino", "cazador", "guerrero"]
const RACE_SLUGS := ["gnomo", "elfo", "humano", "enano", "orco"]

# 5 races x 7 classes = 35 entries. Keys formatted as "class:race" for a flat
# lookup; nested dicts would be denser but harder to grep.
const HINTS := {
	# --- Mago: carry caster, lives or dies by mana + positioning ----------
	"mago:gnomo":    "Pure magic damage. Glass cannon — kite or die.",
	"mago:elfo":     "Balanced caster. Big nukes, decent saves.",
	"mago:humano":   "Textbook mage. No standout, no gaping hole.",
	"mago:enano":    "Battle-mage. Slower casts, but built to take a hit.",
	"mago:orco":     "Tanky caster. Slow but unkillable.",

	# --- Bardo: evasive support caster, AGI-heavy --------------------------
	"bardo:gnomo":   "Whirlwind bard. Dodge, sing, melt — never standing still.",
	"bardo:elfo":    "Evasive support. Magic + dodge, hard to pin.",
	"bardo:humano":  "All-purpose bard. Buffs, debuffs, never out of place.",
	"bardo:enano":   "Front-row bard. Sturdy songs, slow feet.",
	"bardo:orco":    "Brawler bard. Trades agility for raw stamina.",

	# --- Clerigo: hybrid healer, INT for heals + CON to outlast -----------
	"clerigo:gnomo": "Speed-cleric. Fast heals, paper armor — keep your distance.",
	"clerigo:elfo":  "Pristine healer. Refined casts, light on her feet.",
	"clerigo:humano":"Reliable healer-fighter. No standout, no weakness.",
	"clerigo:enano": "Iron priest. Heals slow, but nothing knocks him over.",
	"clerigo:orco":  "Battle-cleric. Heals between hammer-blows.",

	# --- Paladin: melee + magic, INT and STR both matter ------------------
	"paladin:gnomo": "Spell-paladin. Light armor, lethal smites.",
	"paladin:elfo":  "Holy duelist. Magic-strong, agile in a pinch.",
	"paladin:humano":"Storybook paladin. Sword, shield, healing prayer.",
	"paladin:enano": "Sturdy duelist. Trades blows, recovers fast.",
	"paladin:orco":  "Crusader hammer. Heavy plate, heavier vows.",

	# --- Asesino: burst phys, AGI for crits + STR for damage --------------
	"asesino:gnomo": "Hit-and-run burst. Dodge, stab, vanish.",
	"asesino:elfo":  "Shadow ranger. Quick blades, magic-warded.",
	"asesino:humano":"Versatile killer. Patient, balanced, deadly.",
	"asesino:enano": "Brawl-assassin. Trades stealth for staying power.",
	"asesino:orco":  "Headsman build. Slow stalker, one-shot finisher.",

	# --- Cazador: ranged phys, AGI for hits + STR for arrows --------------
	"cazador:gnomo": "Skirmisher archer. Endless mobility, fragile up close.",
	"cazador:elfo":  "Classic ranger. High mobility, magic resilience.",
	"cazador:humano":"Steady marksman. Reliable from any range.",
	"cazador:enano": "Crossbow tank. Slow draws, but takes the hits.",
	"cazador:orco":  "Brute archer. Few shots, each one devastating.",

	# --- Guerrero: tank, CON + STR + PHYS_RES ------------------------------
	"guerrero:gnomo":"Glass tank — fast, but fragile under blows.",
	"guerrero:elfo": "Duelist warrior. Magic-warded, light on his feet.",
	"guerrero:humano":"Standard knight. Trains hard, fights harder.",
	"guerrero:enano":"Iron wall. Anchored, armored, immovable.",
	"guerrero:orco": "Frontline bruiser. Heavy armor, heavier swings.",
}


static func hint_for(class_slug: String, race_slug: String) -> String:
	if class_slug.is_empty() or race_slug.is_empty():
		return ""
	var key := "%s:%s" % [class_slug, race_slug]
	return HINTS.get(key, "")
