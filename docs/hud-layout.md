# HUD layout — world scene

Reference for [scenes/world/world.tscn](../scenes/world/world.tscn) and the matching `@onready` paths in [scenes/world/world.gd](../scenes/world/world.gd). Keep this in sync if you move nodes.

```
World (Node2D)                     game world root; camera follows the player here
├── Camera2D
├── Ground (Node2D)                procedural checkerboard drawer (z_index = -10)
├── PlayerSprite (Node2D)          you (z_index = 10)
├── Entities (Node2D)              other players + NPCs
└── UILayer (CanvasLayer)          screen-space, independent of camera
    └── HUD (Control, full rect)   mouse_filter = IGNORE; overlays the game
        ├── ChatPanel              top-left, fixed height; right edge anchors to screen-right
        │   └── ChatVBox
        │       ├── ChatDisplay (RichTextLabel)
        │       └── ChatInput (LineEdit)
        ├── MinimapPanel           fixed 100×100, anchored to the right edge of the top bundle
        │   └── Minimap (Control)    _MinimapDrawer paints the red player dot here
        ├── RightPanel             right side, 250 wide, full height
        │   └── VBox
        │       ├── ButtonBar (HBox)            Map@XY · FPS · ? · S
        │       ├── HeaderRow (HBox)            big Level | Name + <city>
        │       ├── XPBar + XPLabel
        │       ├── InvTabs (TabContainer)      Inventario | Hechizos
        │       │   ├── Inventario (GridContainer, 5 cols)
        │       │   └── Hechizos  (VBox → SpellList + LANZAR)
        │       ├── StatsTabs (TabContainer, tabs_position = BOTTOM)
        │       │   ├── STATS (HP / MP / stats split / gold)
        │       │   └── MENU  (placeholder buttons)
        │       └── EquipmentRow (HBox: H · A · W · S · MR)
        └── (system messages now route into ChatDisplay; no separate label)
```

## Responsive top bundle

Chat + minimap fill the area left of the right panel and resize with the window. The anchors look like this:

- `ChatPanel`: `anchor_right = 1.0`, `offset_right = -380` → chat width = window − 380
- `MinimapPanel`: `anchor_left = 1.0`, `anchor_right = 1.0`, `offset_left = -370`, `offset_right = -270` → always 100 wide, pinned 10px before the right panel

The `-380` magic number is `right panel (260) + gap (10) + minimap (100) + gap (10)`. Update it if the right panel width changes.

## Focus / input

Every interactive control in the HUD has `focus_mode = 0` so arrow keys can't navigate UI focus. `world.gd::_input` also consumes arrow key events before Godot's GUI layer sees them — belt-and-braces because TabContainer's internal TabBar has historically ignored `focus_mode`.

`ChatInput` is the only focusable control. It only gains focus via explicit `grab_focus()` on T press, and releases on Enter.
