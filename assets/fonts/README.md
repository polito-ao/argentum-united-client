# Fonts

## Cinzel

Used for the title text on the login screen ("Argentum United") and other
display headings as needed.

- **Source**: [Google Fonts — Cinzel](https://fonts.google.com/specimen/Cinzel),
  fetched from the canonical [google/fonts repo](https://github.com/google/fonts/tree/main/ofl/cinzel).
- **License**: SIL Open Font License 1.1 (OFL). Full text in `OFL.txt`.
  Per OFL section 1 the font is bundled with this software and may be
  redistributed; section 4 reserves the "Cinzel" Reserved Font Name to
  the original designers — we ship the unmodified file as-is.
- **File**: `Cinzel-Variable.ttf` is the variable-axis TTF covering the
  full weight range (Regular 400 → Black 900). A single file replaces
  static Regular/SemiBold/Bold TTFs; Godot 4 reads the weight axis via
  `FontVariation` or the `theme_overrides/font_variations` property on a
  Label.

## Why Cinzel

Roman serif with engraved-stone aesthetic — fits Argentum United's
medieval/heroic identity and reads well at large display sizes.

## Modification

Do not modify `Cinzel-Variable.ttf`. If a different cut is needed, ship
a separate sibling file (e.g. `OtherFont-Regular.ttf`) and add a license
note here.
