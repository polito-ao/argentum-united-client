# Client tests (GUT)

GDScript tests using [GUT](https://github.com/bitwes/Gut) v9.4.

## Layout

```
tests/
  unit/         GUT tests for pure script classes (no scene tree)
  integration/  GUT tests that load real scenes — to be added when needed
```

Test file convention: `test_<unit>.gd`, extending `GutTest`. One test method
per behaviour, named `test_<what_it_proves>`.

## Run from CLI

From the client repo root:

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/ -gexit
```

(`godot` must be on PATH and point to your Godot 4.6 binary.)

## Run from the editor

GUT panel appears at the bottom of the Godot editor once
`addons/gut/plugin.cfg` is enabled (already configured in
`project.godot`). Pick `Run All` or a specific test file.

## What's testable today

- Pure GDScript classes under `scripts/` with no scene-tree dependency
  (e.g. `scripts/network/packet_ids.gd`'s static methods,
  `scripts/network/connection.gd`'s `_msgpack_encode/_decode`)
- Extracted controller classes (`scripts/ui/hud_controller.gd` etc.)
  when constructed with stub Controls

## What's not (yet) testable cleanly

`scenes/world/world.gd` is heavily node-tree-coupled. The architecture
review prescribed extracting controllers (HUDController first) so the
extracted pieces become testable without instantiating the world scene.
