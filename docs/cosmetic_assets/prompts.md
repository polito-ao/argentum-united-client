# Cosmetic Asset Generation Prompts

## Purpose

Self-contained, copy-pasteable AI image-generation prompts for **logo
exploration** (5 distinct directions) and the **two key UI backgrounds**
(login screen + character select). Use one section at a time; each is
designed to be dropped directly into FLUX-dev / SDXL / DALL-E-3 /
Midjourney with no extra prep.

The prompts are **lore-anchored**, drawn from
`docs/phase0a/triage-checkpoint.md` in the server repo and the design
section of the server CLAUDE.md. Key beats reflected throughout:

- "Argentum United": coalition / alliance of city-states
- **Citizenship over clans**: players belong to cities, not guilds
- **Loyal Crest**: voluntary allegiance, social proof
- **Eucatastrophe Clock**: 9-10 month world-cycle, escalating threat
  and hopeful resurrection (Tolkien)
- **The Wall at the Pole**: ice barrier, cracks during the cycle as
  the visible signal
- **Gates**: instanced dungeon doors, ~70% combat / 30% puzzle
- **10 cities** including La Guardia (rogue city at the Pole), Tanaris
  (Tierras Perdidas tribute), Unberogen (Frost AO tribute)
- "Honors AO community while introducing modern game design"

## Tooling notes

Realistic options for generating these, in order of recommended fit:

| Tool | Strengths | Notes |
|---|---|---|
| **Midjourney v6+** | Best for cinematic backgrounds, painterly oil-painting style, "epic" framing | Web-only; no local script. Best fit for the two backgrounds. |
| **FLUX-dev** (via Replicate or local ComfyUI) | Best prompt adherence, best for logos with shape constraints, supports negative-prompt-style guidance | A Replicate API call from a 20-line Python script is the simplest path. |
| **FLUX-schnell** (Replicate) | Faster + cheaper than `dev`, slightly less detailed | Good for iteration / variant runs once a direction is chosen. |
| **Stability SDXL** | Cheap, mature ControlNet ecosystem, good for tile-based art | Use if you want to lock composition with a sketch. |
| **OpenAI DALL-E 3** | Strong text-rendering (useful for wordmark variants), conservative outputs | Worse at the "epic dark fantasy" register than Midjourney. |

**Suggested workflow** for the user:

1. **Logos**: run prompts 1-5 through FLUX-dev on Replicate (one-shot
   each, request 4 variants). Pick a direction, then iterate within it.
2. **Backgrounds**: Midjourney v6 with the prompt verbatim, request
   4 variants, upscale the winner. Falls back to FLUX-dev if Midjourney
   subscription is not available.
3. **Wordmark variants** (logo + "Argentum United" text): generate text
   in DALL-E 3 separately, composite manually. Image models still
   hallucinate medieval-style typography badly.

A starter `replicate` Python script lives in the team notes (not
committed). For ad-hoc generation the web UIs are fine; this doc just
needs to provide the prompts themselves.

## Conventions for every prompt below

- **Aspect ratio** is stated explicitly per prompt.
- **Negative prompts** are standardized: `no anime, no cartoon, no chibi,
  no low-poly, no pixel art, no watermark, no signature, no text artifacts,
  no extra limbs, no malformed hands` --- append to every prompt unless a
  prompt opts in to text (e.g. wordmark logos).
- For Midjourney, replace `negative prompts` syntax with `--no anime,
  cartoon, chibi, watermark, text` style flags.

---

## TABLE OF CONTENTS

1. [Logo direction 1 --- Heraldic shield](#logo-1)
2. [Logo direction 2 --- Eucatastrophe hourglass](#logo-2)
3. [Logo direction 3 --- Coalition banners](#logo-3)
4. [Logo direction 4 --- Fortress and crown](#logo-4)
5. [Logo direction 5 --- The Wall cracking](#logo-5)
6. [Login background --- epic vista](#bg-login)
7. [Character select background --- cozy tavern interior](#bg-charselect)

---

## <a id="logo-1"></a>Logo 1 --- Heraldic Shield

**Concept**: A coat-of-arms-style emblem. Classic medieval heraldry
treatment, monogram or crossed-weapons device on the shield. The
"Argentum United" mark for players who want a sober, timeless feel.

**Why this direction is distinct**: it leans on **heraldry tradition**
specifically --- symmetry, quartered field, mantling --- versus the
other four which lean on motion (hourglass), interlock (banners),
architecture (fortress) or breakage (wall).

**Prompt**:

> A heraldic shield emblem, frontal view, perfectly symmetrical,
> rendered in burnished silver and aged gold leaf on a deep midnight-blue
> field. The shield is quartered: upper-left and lower-right quadrants
> bear a stylized longsword crossed with a balance scale (justice +
> defense, the union of the cities); upper-right and lower-left quadrants
> bear a small castle silhouette flanked by laurel branches. At the top
> of the shield, an "AU" monogram in serif blackletter, fused into the
> chief band. Mantling drapes naturally around the shield in muted
> crimson with silver trim. Behind the shield, two crossed banner poles
> with furled cloth pennants. Style: classic European heraldry, museum
> quality, realistic embossed metal texture, subtle scuff and patina to
> suggest centuries of use, not pristine. Lighting: soft frontal,
> studio-grade, slight rim light from upper left to bring out the
> embossing. Background: solid charcoal-black with very subtle parchment
> texture, vignette to focus the eye. The emblem should read clearly at
> small sizes (favicon-friendly silhouette).
>
> Negative prompts: no anime, no cartoon, no chibi, no low-poly, no
> pixel art, no watermark, no signature, no fluorescent colors, no
> modern fonts, no clip-art look, no flat vector illustration, no skulls
> (too edgy), no dragons (too generic).

**Suggested model + tags**:
- **FLUX-dev**, 1024x1024, guidance 4.0, 28 steps.
- Style tags: `heraldry, coat of arms, embossed metal, museum-quality,
  cinematic studio lighting`.
- **Aspect ratio**: 1:1 (icon).
- **Wordmark variant**: generate separately. Prompt: "The words
  Argentum United in a custom blackletter-serif hybrid typeface,
  burnished silver with a thin gold outline, on a charcoal background,
  centered, 16:9 banner crop, museum poster quality." Composite under
  the icon manually.

---

## <a id="logo-2"></a>Logo 2 --- Eucatastrophe Hourglass

**Concept**: An hourglass with sand falling through, a sword crossing
its waist diagonally. Captures "the world has a heartbeat" --- the
9-10 month cycle is the soul of the game. The hourglass is being held
upright by something hopeful, not just running out: the falling sand
glows gold, suggesting resurrection at the bottom.

**Why this direction is distinct**: this is the only direction that
**tells time** as part of the brand. Mortality + resurrection.
Tolkien's Eucatastrophe is the philosophical core of the game; this
logo says it out loud without text.

**Prompt**:

> An ornate medieval hourglass, vertical, frontal view, centered on a
> deep void-black background. The hourglass frame is wrought iron with
> silver filigree at the caps. Inside the upper bulb, sand glows a soft
> ember-orange, suggesting embers more than dust. The falling sand
> stream is a thin column of bright gold light, and at the moment it
> hits the lower bulb, it bursts into faint white-gold sparks (small,
> tasteful --- three or four sparks, not a fireworks effect). The lower
> bulb is two-thirds full and softly lit from within. A longsword,
> blade plain and well-used (not jeweled), is laid diagonally across the
> hourglass at the waist, point to upper-right, hilt to lower-left.
> The sword is silver, clean, single-edged style, no flourishes --- it
> represents the hero who carries on across cycles. Faint silver mist
> curls around the base of the hourglass, suggesting a clock face just
> below the frame (hint, do not render explicitly). Style: dark fantasy
> oil painting, baroque metalwork, photorealistic textures, dramatic
> single-source lighting from frontal-upper-left, deep contrast, the
> object is the hero of the frame. Background: pure black with a faint
> radial vignette of dusty gold leaking from behind the hourglass ---
> the impression of dawn at the edge of darkness.
>
> Negative prompts: no anime, no cartoon, no chibi, no neon colors, no
> Photoshop lens flares, no skulls, no Reaper imagery, no zodiac
> symbols, no watermark, no signature, no text artifacts, no clock
> hands rendered explicitly, no broken glass shards.

**Suggested model + tags**:
- **FLUX-dev** for shape fidelity, or **Midjourney v6** for the
  painterly mood (try both, pick).
- 1024x1024, guidance 3.5, 32 steps (Flux). Midjourney: `--ar 1:1
  --style raw --stylize 250`.
- Style tags: `dark fantasy, oil painting, baroque ironwork, dramatic
  chiaroscuro, ember glow`.
- **Aspect ratio**: 1:1 icon. A horizontal wordmark variant works
  beautifully --- generate "Argentum United" in a thin elegant serif
  and set it below the hourglass at half height.

---

## <a id="logo-3"></a>Logo 3 --- Coalition Banners

**Concept**: Three to five banners interlocked at their poles, each
banner bearing a different city sigil (a stylized castle, a mountain,
a sea wave, a forest tree, a flame). The poles meet at a single point
behind, creating a "coalition" knot. Strong reference to the
"United" half of the brand --- citizenship over clans, cities banding
together, the Loyal Crest as a personal pledge to a city.

**Why this direction is distinct**: this is the only logo that **shows
plurality**. The other four are singular objects. This one says "many
peoples, one cause."

**Prompt**:

> Five medieval banners arranged radially, their poles meeting at a
> single hidden point at the center, the cloth of each banner fanning
> outward like a star. Each banner is a different muted color --- deep
> crimson, forest green, ocean teal, sand-ochre, ice-pale --- and bears
> a different stylized city sigil embroidered in pale silver: a
> turreted castle, a snow-capped mountain peak, a cresting wave with
> sea-foam, a single broad oak tree, a single steady flame. The cloth
> is heavy wool, slightly weathered at the edges, with believable folds
> and pole-shadow on the underside. The poles are dark stained oak with
> simple iron caps. At the very center where the poles converge, a
> small silver disc with an etched "AU" monogram serves as the
> binding clasp. Style: heroic medieval banner-painting tradition,
> oil-on-canvas texture, soft directional lighting from the upper left,
> rich warm-shadow contrast, museum-poster composition, symmetrical
> but not rigid. The whole emblem should sit cleanly on a dark slate
> background with very subtle dust motes catching the light.
>
> Negative prompts: no anime, no cartoon, no chibi, no flat vector
> illustration, no clip-art, no modern flag designs, no national flags,
> no stripes, no stars-and-bars, no watermark, no signature, no text
> beyond the central monogram, no neon colors.

**Suggested model + tags**:
- **FLUX-dev** preferred (color discipline + shape fidelity).
- 1024x1024, guidance 4.0, 28 steps.
- Style tags: `medieval heraldry, oil painting, banner art, symmetrical
  composition, painterly`.
- **Aspect ratio**: 1:1. The monogram can act as the favicon-scale
  silhouette; the full radial banner spread is the marketing-scale
  mark.
- **Wordmark variant**: not needed --- the central AU disc is the
  wordmark.

---

## <a id="logo-4"></a>Logo 4 --- Fortress and Crown

**Concept**: A silhouette of a citadel --- towers, walls, a single
gate --- with a crown floating above it. The crown is **earned, not
bestowed**: simple iron with five small unadorned points, no jewels.
Says "this kingdom is built by its players, governed by its people"
(the Governor system: citizens elect leadership). Regal but humble.

**Why this direction is distinct**: this is the only direction that
foregrounds **architecture**. The fortress silhouette is the city ---
which is the player's home in this game. Citizenship made visible.

**Prompt**:

> A silhouette of a fortified medieval citadel, frontal view, rendered
> in solid deep-charcoal against a soft sunrise sky. The citadel has
> three main towers (left tall, center tallest with a peaked roof,
> right shorter and rounded), connected by a curtain wall with crenelations.
> A single arched gate sits in the center of the wall, lit very faintly
> from within in warm orange. Above the citadel, floating about
> one tower-height up, a simple iron crown --- five unadorned points,
> hammered metal texture, no jewels, the kind of crown a republic
> would forge. The crown is rendered with proper highlight and shadow,
> not flat. Behind everything, the sky is a vertical gradient: deep
> indigo at the top fading to a warm dusty rose at the horizon, with a
> single thin band of pale gold where the sun has just risen behind
> the citadel --- the citadel reads as silhouette, the crown reads as
> rendered metal, the contrast is intentional. Style: heroic landscape
> oil painting, Caspar David Friedrich mood, painterly silhouette,
> single sunrise light source, no figures, no banners, no animals.
> Composition: citadel occupies the lower 60% of the frame (centered),
> crown floats in upper third, sky fills the rest. The frame should
> work as a shape (silhouette readable at favicon size) and as a full
> illustration (atmospheric at marketing size).
>
> Negative prompts: no anime, no cartoon, no chibi, no Disney castle
> shape, no jewels on the crown, no figures, no banners on the towers,
> no watermark, no signature, no text, no Christian crosses, no
> Disney-style spires.

**Suggested model + tags**:
- **Midjourney v6** strongly preferred for the painterly sky.
  Alternative: **FLUX-dev**.
- Midjourney: `--ar 1:1 --style raw --stylize 350`.
- Style tags: `heroic oil painting, sunrise silhouette, romantic
  landscape, single-light-source, painterly`.
- **Aspect ratio**: 1:1 icon. Wordmark variant: "Argentum United" in
  a tall thin engraver-style serif, generated separately, set below the
  silhouette in marketing crops.

---

## <a id="logo-5"></a>Logo 5 --- The Wall Cracking

**Concept**: A weathered stone wall fills the frame; silver-and-gold
hairline cracks spread across it from the top, just beginning to glow
from within. Direct reference to **The Wall at the Pole** --- its
cracks during the Eucatastrophe Clock are the in-world signal that
the cycle is turning. This logo says: "the world is about to break,
and that is the good news."

**Why this direction is distinct**: this is the only direction that
captures the **threat** half of the Eucatastrophe --- beautiful damage,
the moment before resurrection. It is also the most modern-feeling of
the five (closest to a contemporary game-studio logo register).

**Prompt**:

> A close-up of an ancient, weathered stone wall, rendered photo-real
> with dense moss in the lower seams and frost crystals in the upper
> cracks. The wall fills the entire frame --- no horizon, no sky. From
> the top edge of the frame, a network of fine cracks branches downward
> across the stone, growing wider as they descend, like lightning frozen
> in masonry. Inside the cracks, a soft cool light glows: pale silver
> at the top, deepening to warm gold at the bottom --- the impression
> that something is waking up inside the wall, not destroying it.
> Around two of the larger cracks, a few stone fragments hang in mid-air,
> caught at the moment of breakage but not yet fallen. Centered on the
> wall, faintly etched into the stone (carved long ago, weathered down
> to almost a memory), the "AU" monogram in a stark Roman-square
> serif. The monogram is darker than the surrounding stone --- a shadow,
> not a highlight. Style: dark fantasy concept art, photorealistic
> stone and ice texture, cinematic lighting from inside the cracks
> only (the cracks are the only light source), high contrast,
> painterly edge to the floating fragments. The composition should
> read as both threat and promise.
>
> Negative prompts: no anime, no cartoon, no chibi, no neon colors, no
> lava (cracks are silver-gold, not red), no demonic imagery, no eyes
> in the cracks, no characters, no figures, no watermark, no
> signature, no clip-art look, no glossy plastic finish.

**Suggested model + tags**:
- **FLUX-dev** for the texture fidelity. **Midjourney v6** also good.
- 1024x1024, guidance 3.8, 30 steps (Flux). MJ: `--ar 1:1 --style raw
  --stylize 400`.
- Style tags: `dark fantasy, photorealistic stone, cinematic crack
  glow, concept art`.
- **Aspect ratio**: 1:1. The favicon read is the AU monogram + the
  brightest crack --- verify silhouette legibility at 32x32. Wordmark
  variant: same AU monogram from the wall, isolated, on transparent
  background, with "Argentum United" set below in a clean modern
  serif.

---

## <a id="bg-login"></a>Login Screen Background --- Epic Vista

**Concept**: The login screen is the player's first impression every
session. It must read as **LotR / Game-of-Thrones epic** --- never
cartoonish, never small. The user prefers The Wall at the Pole with a
storm gathering, with the Eucatastrophe sky overhead. Wide vista,
breathing room, no UI clutter implied.

**Aspect ratio**: 16:9 (1920x1080 minimum; ideal output 3840x2160 for
retina-friendly downscale).

**Prompt**:

> A vast cinematic landscape, looking northward across a snow-blasted
> tundra toward The Wall --- an immense ice-and-stone barrier that
> stretches the full width of the horizon, taller than any structure in
> the world, rising into low storm cloud. Hairline cracks of pale
> silver-gold light run vertically down the face of the Wall, a few
> wide enough to see through, glowing faintly from within --- the
> Eucatastrophe Clock has begun to turn. The sky above is a bruised
> drama of slate-blue, charcoal, and a thin slash of dawn-rose just at
> the horizon line behind the Wall, where the sun is hidden. Volumetric
> snow drifts across the foreground, low to the ground, catching the
> stray light. In the middle distance, perhaps one-third of the way
> from the lower frame edge, a single small figure stands on a low
> rocky outcrop --- a lone hero in a heavy traveler's cloak, back to the
> viewer, facing the Wall, scaled tiny against the immensity of the
> landscape. The figure has a longsword sheathed at the hip and a
> simple shield slung across the back --- no logos, no banners, no
> identifying marks. The hero is the witness, not the subject. In the
> far distance to the left and right of the Wall, the faint silhouette
> of two distant city watchtowers can be made out --- La Guardia, the
> rogue city at the Pole, on the right; an unnamed allied watch-fort
> on the left --- both barely visible through the storm haze, suggesting
> the coalition holds the line. Style: cinematic concept art, oil-on-
> canvas painterly finish but photorealistic textures, dramatic
> single-light-source lighting (the sliver of dawn behind the Wall is
> the only true light, everything else is reflected), volumetric fog,
> high dynamic range, golden hour palette pushed cool toward deep blues
> and steel grays. Reference: Lord of the Rings landscape paintings by
> Alan Lee and John Howe; Game of Thrones North-of-the-Wall
> establishing shots; Frazetta's atmospheric depth. Wide composition,
> rule-of-thirds with the Wall on the upper third line and the
> figure on the lower-left third intersection. Frame must read with
> empty space top-center for game logo overlay, and clean lower-third
> region for login form overlay.
>
> Negative prompts: no anime, no cartoon, no chibi, no low-poly, no
> pixel art, no watermark, no signature, no text, no UI mockup, no
> visible HUD, no modern weapons, no firearms, no horses, no large
> figures, no dragons, no obvious creature monsters, no neon colors,
> no purple-pink fantasy palette (keep it cold and grounded).

**Suggested model + tags**:
- **Midjourney v6** strongly preferred --- best painterly cinematic
  landscape engine.
- `--ar 16:9 --style raw --stylize 500 --quality 1`.
- Alternative: **FLUX-dev** at 1920x1080 with cinematic style tags.
- Style tags: `cinematic concept art, Alan Lee, John Howe, LotR
  landscape, oil painting, photorealistic textures, dramatic dawn
  light, volumetric fog`.
- Generate 4 variants, upscale the winner, downscale to 1920x1080 for
  shipping (keep the high-res master in the asset Drive).

---

## <a id="bg-charselect"></a>Character Select Background --- Cozy Tavern Interior

**Concept**: After the epic login, the character select screen should
feel **intimate and human-scale**. Witcher-tavern simplicity: cozy
medieval interior, fire going, wooden beams, warm shadows. The
implicit read is that the player has just walked into the Shrine of
Fortune common room or a city tavern, and is about to choose which
hero to send out today. No NPCs visible --- the room is the player's
own POV the moment they entered.

**Aspect ratio**: 16:9 (matching the login background).

**Prompt**:

> The interior of a small medieval tavern common room, viewed from
> just inside the doorway looking toward the far wall. A large stone
> fireplace dominates the right-hand wall, with a healthy fire going ---
> orange and gold flames, a few floating embers, soot-blackened stone
> around the hearth, an iron pot hanging on a hook to one side. The
> ceiling is low, with thick dark-stained wooden beams running
> front-to-back; one beam hangs an old iron lantern, lit, casting a
> warm pool of light on the floor below. The walls are rough plastered
> stone, ochre with age, decorated with two weathered tapestries --- one
> shows a faded city sigil (a tower silhouette), the other a faded
> mountain range --- both small enough to feel like local history rather
> than ostentation. To the left, a small mullioned window with leaded
> glass lets in cool blue late-afternoon light, providing the only
> cool tone in the room and beautifully contrasting the firelight.
> A long heavy oak table runs through the middle distance, with three
> empty wooden benches; on the table, a few practical objects
> suggesting recent use --- a clay mug, a half-eaten loaf of bread, a
> rolled parchment map weighted down with a small dagger, an unlit
> candle in a brass holder. The floor is wide-plank wood, scuffed and
> stained, with a faded woven rug near the fireplace. **No people,
> no NPCs, no characters in the frame** --- the room is empty, waiting,
> as if the player has just stepped in. The composition leaves the
> center of the frame deliberately uncluttered: the table sits in the
> middle ground but its surface is sparse enough that character cards
> can be overlaid in the central horizontal band without fighting the
> art. Style: oil painting, ambient warm light from the fire on the
> right and cool light from the window on the left meeting in the
> middle, photorealistic textures with painterly edges, intimate
> framing, "you are here" mood. Reference: The Witcher 3 inn
> interiors (Crossroads, Crow's Perch); Dutch Golden Age genre
> paintings (Vermeer interiors, Pieter de Hooch); Skyrim mead-hall
> warmth without the high fantasy gloss. Slight depth of field ---
> the table sharpest, the back wall and fireplace softer.
>
> Negative prompts: no anime, no cartoon, no chibi, no low-poly, no
> pixel art, no watermark, no signature, no text, no UI mockup, no
> visible characters, no people, no humans, no NPCs, no animals (no
> cat by the fire, please --- too cute), no high-fantasy ornamentation,
> no neon colors, no fluorescent lighting, no obvious shop signage, no
> tavern wenches, no bartender behind a bar, no large open kitchens.

**Suggested model + tags**:
- **Midjourney v6** preferred for the painterly genre-painting feel.
  Alternative: **FLUX-dev**.
- `--ar 16:9 --style raw --stylize 400 --quality 1`.
- Style tags: `Dutch Golden Age interior, Vermeer light, Witcher tavern,
  oil painting, warm-cool color contrast, intimate framing, no figures`.
- Generate 4 variants. Pick the one with the cleanest central
  horizontal band --- it must accept the overlay of three FIFA-style
  character cards without competing.
- Downscale to 1920x1080 for shipping; keep high-res master in the
  asset Drive.
