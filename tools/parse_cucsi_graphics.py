#!/usr/bin/env python3
"""
Parse Cucsi graphics .ini/.dat files and emit per-catalog YAML + JSON
describing bodies, heads, helmets, weapons, shields, and effects ready for
the Godot client's SpriteCatalog autoload.

Source files (Windows-1252 encoded) live at
    C:/Users/agusp/Documents/Cucsiii/clientecucsi/Init/

Outputs:
    assets/sprite_data/bodies.yml         (+ .json sibling)
    assets/sprite_data/heads.yml          (+ .json)
    assets/sprite_data/helmets.yml        (+ .json)
    assets/sprite_data/weapons.yml        (+ .json)
    assets/sprite_data/shields.yml        (+ .json)
    assets/sprite_data/effects.yml        (+ .json)
    assets/sprite_data/items.yml          (+ .json)
    assets/sprite_data/missing_refs.txt   (skip log, not data)

Rules:
  - All pixel coords (Graficos region X/Y/W/H, body HeadOffsetX/Y) are
    pre-doubled before being written. Identifiers, frame counts, and
    speeds (ms) are unchanged.
  - Walk1..Walk4 mapping uses the Spanish in-file comments:
        Walk1 = arriba   -> walk_north
        Walk2 = derecha  -> walk_east
        Walk3 = abajo    -> walk_south
        Walk4 = izq      -> walk_west
    (The original brief proposed S/N/E/W; the actual files mark
    arriba/derecha/abajo/izq, which is what's used here.)
  - Single-frame GRH -> 1-frame animation with speed_ms=0.
  - Multi-frame GRH -> sub-GRHs resolved + their files referenced; the
    multi-frame entry's own file/region fields are ignored (sub-GRHs are
    the real frames).
  - Any reference to a missing GRH or a missing PNG in
    assets/upscaled_2x/ -> skip the catalog entry entirely and log to
    missing_refs.txt.
"""

from __future__ import annotations

import codecs
import json
import os
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional, Tuple

# ---------------------------------------------------------------------------
# Paths

CUCSI_INIT = Path(r"C:/Users/agusp/Documents/Cucsiii/clientecucsi/Init")
CUCSI_DAT = Path(r"C:/Users/agusp/Documents/Cucsiii/servercucsi/Dat")
CLIENT_ROOT = Path(__file__).resolve().parent.parent
UPSCALED_DIR = CLIENT_ROOT / "assets" / "upscaled_2x"
OUT_DIR = CLIENT_ROOT / "assets" / "sprite_data"
MISSING_LOG = OUT_DIR / "missing_refs.txt"

# Server's authoritative items.yml. Every `icon_grh_id` referenced here MUST
# resolve to an entry in the emitted client catalog, otherwise dropped items
# / inventory tiles will fall back to a yellow ColorRect at runtime.
SERVER_ITEMS_YML = CLIENT_ROOT.parent / "argentum-united-server" / "config" / "items.yml"

DIR_NAMES = ("walk_north", "walk_east", "walk_south", "walk_west")
# Walk1=arriba, Walk2=derecha, Walk3=abajo, Walk4=izq -> N, E, S, W

# ---------------------------------------------------------------------------
# INI reader (tolerant of Cucsi's `key=value\t' comment` lines)

_section_re = re.compile(r"^\[([^\]]+)\]")
# Cucsi tolerates inline comments after the section header, e.g.
#   [OBJ16] 'CASA RUINAS
#   [OBJ46]'Nieve 1
# A strict `\]\s*$` rejects those headers entirely; the parser then keeps
# writing keys into the *previous* section, silently overwriting fields.
# That's how Daga's `GrhIndex=510` got clobbered with OBJ16's `GrhIndex=5600`.
# We now match the bracketed name at the start of the line and ignore the
# rest. (KV lines stay strict; they're already comment-stripped below.)
_kv_re = re.compile(r"^([A-Za-z0-9_]+)\s*=\s*([^\r\n]*)$")


def parse_ini(path: Path) -> Dict[str, Dict[str, str]]:
    sections: Dict[str, Dict[str, str]] = {}
    current: Optional[str] = None
    with codecs.open(str(path), "r", encoding="cp1252") as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith(";"):
                continue
            m = _section_re.match(line)
            if m:
                current = m.group(1)
                sections.setdefault(current, {})
                continue
            if current is None:
                continue
            m = _kv_re.match(line)
            if not m:
                continue
            key, val = m.group(1), m.group(2)
            # Strip Cucsi's inline `' arriba` / tab comment.
            for sep in ("'", ";", "\t"):
                idx = val.find(sep)
                if idx >= 0:
                    val = val[:idx]
            sections[current][key] = val.strip()
    return sections


# ---------------------------------------------------------------------------
# Graficos.ini -> GRH index

@dataclass
class GrhEntry:
    grh_id: int
    num_frames: int
    # Single-frame fields:
    file_num: Optional[int] = None
    x: int = 0
    y: int = 0
    w: int = 0
    h: int = 0
    # Multi-frame fields:
    sub_ids: List[int] = field(default_factory=list)
    speed_ms: int = 0


def load_graficos(path: Path) -> Dict[int, GrhEntry]:
    """
    Cucsi format (text):
      Single: Grh{N}={NumFrames=1}-{FileNum}-{X}-{Y}-{W}-{H}
      Anim:   Grh{N}={NumFrames>1}-{Sub1}-{Sub2}-...-{SubN}-{Speed}
    """
    grhs: Dict[int, GrhEntry] = {}
    with codecs.open(str(path), "r", encoding="cp1252") as f:
        for raw in f:
            line = raw.strip()
            if not line or not line.startswith("Grh"):
                continue
            eq = line.find("=")
            if eq < 0:
                continue
            try:
                grh_id = int(line[3:eq])
            except ValueError:
                continue
            parts = line[eq + 1 :].split("-")
            if len(parts) < 2:
                continue
            try:
                num_frames = int(parts[0])
            except ValueError:
                continue
            entry = GrhEntry(grh_id=grh_id, num_frames=num_frames)
            if num_frames == 1:
                # Expect: 1-{File}-{X}-{Y}-{W}-{H}
                if len(parts) < 6:
                    continue
                try:
                    entry.file_num = int(parts[1])
                    entry.x = int(parts[2])
                    entry.y = int(parts[3])
                    entry.w = int(parts[4])
                    entry.h = int(parts[5])
                except ValueError:
                    continue
            else:
                # Expect: N-{sub1}-...-{subN}-{speed}
                if len(parts) < num_frames + 2:
                    continue
                try:
                    entry.sub_ids = [int(p) for p in parts[1 : 1 + num_frames]]
                    entry.speed_ms = int(parts[1 + num_frames])
                except ValueError:
                    continue
            grhs[grh_id] = entry
    return grhs


# ---------------------------------------------------------------------------
# Catalog parsers

def _read_dir_grhs(section: Dict[str, str], keys: Tuple[str, ...]) -> Optional[List[int]]:
    """Read 4 keys (e.g. Walk1..Walk4 or Head1..Head4 or Dir1..Dir4) -> grh ids.

    Returns None if any key is missing. Returns the list (with zeros) otherwise;
    a 0 grh id signals "no sprite for this direction" — caller decides.
    """
    out: List[int] = []
    for k in keys:
        if k not in section:
            return None
        try:
            out.append(int(section[k]))
        except ValueError:
            return None
    return out


def parse_bodies(ini_path: Path) -> Dict[int, Dict]:
    sections = parse_ini(ini_path)
    out: Dict[int, Dict] = {}
    for sec, kv in sections.items():
        m = re.match(r"^BODY(\d+)$", sec)
        if not m:
            continue
        bid = int(m.group(1))
        walks = _read_dir_grhs(kv, ("Walk1", "Walk2", "Walk3", "Walk4"))
        if walks is None:
            continue
        try:
            hox = int(kv.get("HeadOffsetX", "0"))
            hoy = int(kv.get("HeadOffsetY", "0"))
        except ValueError:
            hox, hoy = 0, 0
        out[bid] = {
            "walk_grhs": walks,            # [N, E, S, W]
            "head_offset": (hox, hoy),     # raw, will ×2 later
        }
    return out


def parse_heads_like(ini_path: Path, section_pattern: re.Pattern, keys: Tuple[str, ...]) -> Dict[int, List[int]]:
    """
    Parses a 4-direction grh-only catalog (Cabezas, Cascos, Armas, Escudos).
    section_pattern must capture the numeric id in group(1).
    """
    sections = parse_ini(ini_path)
    out: Dict[int, List[int]] = {}
    for sec, kv in sections.items():
        m = section_pattern.match(sec)
        if not m:
            continue
        cid = int(m.group(1))
        grhs = _read_dir_grhs(kv, keys)
        if grhs is None:
            continue
        out[cid] = grhs
    return out


# ---------------------------------------------------------------------------
# Fxs.ini parser

@dataclass
class FxEntry:
    fx_id: int
    grh_id: int
    offset_x: int
    offset_y: int


def parse_fxs(ini_path: Path) -> Dict[int, FxEntry]:
    """
    Cucsi Fxs.ini layout:
      [INIT]
      NumFxs=N
      [FX{n}]
      Animacion={GrhId}
      OffsetX={int}
      OffsetY={int}
    """
    sections = parse_ini(ini_path)
    out: Dict[int, FxEntry] = {}
    for sec, kv in sections.items():
        m = re.match(r"^FX(\d+)$", sec)
        if not m:
            continue
        fx_id = int(m.group(1))
        try:
            grh_id = int(kv.get("Animacion", "0"))
            ox = int(kv.get("OffsetX", "0"))
            oy = int(kv.get("OffsetY", "0"))
        except ValueError:
            continue
        out[fx_id] = FxEntry(fx_id=fx_id, grh_id=grh_id, offset_x=ox, offset_y=oy)
    return out


# Effect catalog: argentum-united effect_id -> Cucsi (source_file, fx_index).
# Server constants: scripts/game/layered_character.gd EFFECT_*.
# Each entry's `name` is the YAML key the catalog gets emitted under so the
# Godot side can look it up by effect_id (the numeric id on the wire). Add
# new effects here as the server starts broadcasting them.
EFFECT_MAP: List[Dict] = [
    {
        "id": 1,
        "name": "effect_meditation",
        "source_file": "Fxs.ini",
        "fx_index": 4,   # FX4 = FxMeditar.CHICO (Cucsi level 1-7 default)
    },
    {
        "id": 2,
        "name": "effect_meditation_mediano",
        "source_file": "Fxs.ini",
        "fx_index": 5,   # FX5 = FxMeditar.MEDIANO (Cucsi level 15-22 upgrade)
    },
    {
        "id": 3,
        "name": "effect_meditation_grande",
        "source_file": "Fxs.ini",
        "fx_index": 6,   # FX6 = FxMeditar.GRANDE (Cucsi level 30-37 upgrade)
    },
    # --- Issue #22: dormant catalog entries (server does not emit yet) ------
    # IDs 4-7 are scaffolding for future EFFECT_START emissions. Sourced from
    # Cucsi's spell FX catalog (Hechizos.dat -> FXgrh -> Fxs.ini[FXgrh]) so the
    # PNG / region metadata round-trips through the existing Fxs.ini pipeline.
    {
        "id": 4,
        "name": "effect_blessing_real",
        "source_file": "Fxs.ini",
        # FX9 = "Bendicion de Sortilego" (Hechizos.dat[HECHIZO40]). Golden
        # blessing aura; the most direct Cucsi analogue for "Royal Army"
        # (Bendicion Real) until a faction-specific FX is authored.
        "fx_index": 9,
    },
    {
        "id": 5,
        "name": "effect_blessing_caos",
        "source_file": "Fxs.ini",
        # FX13 = "Apocalipsis" (Hechizos.dat[HECHIZO25/65/76]). Dark/fiery
        # 21-frame burst; placeholder for "Legion Caos" blessing until a
        # bespoke chaos-aura FX is authored.
        "fx_index": 13,
    },
    {
        "id": 6,
        "name": "effect_status_paralysis",
        "source_file": "Fxs.ini",
        # FX8 = "Paralizar" (Hechizos.dat[HECHIZO9/93]). Electric/freeze halo
        # — used by Cucsi as the spell-cast FX; we reuse it as the persistent
        # status marker on the affected character.
        "fx_index": 8,
    },
    {
        "id": 7,
        "name": "effect_status_poison",
        "source_file": "Fxs.ini",
        # FX3 = "Envenenar" (Hechizos.dat[HECHIZO4]). Green poison cloud —
        # spell-cast FX in Cucsi, repurposed as the persistent poison-status
        # marker.
        "fx_index": 3,
    },
]


def build_effect_catalog(
    fxs: Dict[int, FxEntry],
    grhs: Dict[int, GrhEntry],
    upscaled: set,
    missing: List[str],
) -> Dict[str, Dict]:
    """
    Resolve every entry in EFFECT_MAP into a self-contained dict:
        {
          id: int,
          source: "Fxs.ini[N]",
          offset: { x, y } (x2 applied),
          animation: { frames: [...], speed_ms, loop: true },
        }
    Missing GRH or PNG -> skip the entry, log to missing_refs, leave the
    placeholder fallback in the client.
    """
    out: Dict[str, Dict] = {}
    for spec in EFFECT_MAP:
        eid = spec["id"]
        name = spec["name"]
        src_file = spec["source_file"]
        fx_index = spec["fx_index"]
        if src_file != "Fxs.ini":
            # Other source files (Auras.ini, particulas.ini) not wired yet.
            missing.append(
                f"effect {name} (id={eid}): source_file={src_file} not supported"
            )
            continue
        fx = fxs.get(fx_index)
        if fx is None:
            missing.append(
                f"effect {name} (id={eid}): Fxs.ini[{fx_index}] missing"
            )
            continue
        ctx = f"effect {name} (id={eid}, Fxs.ini[{fx_index}], Grh{fx.grh_id})"
        anim = resolve_animation(fx.grh_id, grhs, upscaled, missing, ctx)
        if anim is None:
            missing.append(f"effect {name} (id={eid}): skipping (animation unresolved)")
            continue
        # Default speed if Cucsi did not specify one (single-frame, etc.).
        speed_ms = int(anim.get("speed_ms", 0)) or 1000
        out[name] = {
            "id": eid,
            "source": f"{src_file}[{fx_index}]",
            "offset": {"x": fx.offset_x * 2, "y": fx.offset_y * 2},
            "animation": {
                "frames": anim["frames"],
                "speed_ms": speed_ms,
                "loop": True,
            },
        }
    return out


# ---------------------------------------------------------------------------
# Resolve a single-frame GRH -> {file, region} (with ×2 applied), or fail.

def resolve_single_frame(
    grh_id: int,
    grhs: Dict[int, GrhEntry],
    upscaled: set,
    missing: List[str],
    context: str,
) -> Optional[Dict]:
    if grh_id == 0:
        missing.append(f"{context}: grh_id=0 (placeholder/empty slot)")
        return None
    entry = grhs.get(grh_id)
    if entry is None:
        missing.append(f"{context}: Grh{grh_id} not in Graficos.ini")
        return None
    if entry.num_frames != 1:
        missing.append(
            f"{context}: Grh{grh_id} expected single-frame, got num_frames={entry.num_frames}"
        )
        return None
    if entry.file_num is None:
        missing.append(f"{context}: Grh{grh_id} missing file_num")
        return None
    file_name = f"{entry.file_num}.png"
    if file_name not in upscaled:
        missing.append(f"{context}: Grh{grh_id} -> {file_name} not in assets/upscaled_2x/")
        return None
    return {
        "file": file_name,
        "region": {
            "x": entry.x * 2,
            "y": entry.y * 2,
            "w": entry.w * 2,
            "h": entry.h * 2,
        },
    }


def resolve_animation(
    grh_id: int,
    grhs: Dict[int, GrhEntry],
    upscaled: set,
    missing: List[str],
    context: str,
) -> Optional[Dict]:
    """
    Returns {frames: [{file, region}, ...], speed_ms: int} or None.
    Single-frame GRH -> 1-frame animation, speed_ms=0.
    Multi-frame GRH  -> N frames from sub-GRHs.
    Any missing reference -> abort (return None) and log.
    """
    if grh_id == 0:
        missing.append(f"{context}: grh_id=0 (placeholder/empty slot)")
        return None
    entry = grhs.get(grh_id)
    if entry is None:
        missing.append(f"{context}: Grh{grh_id} not in Graficos.ini")
        return None
    if entry.num_frames == 1:
        frame = resolve_single_frame(grh_id, grhs, upscaled, missing, context)
        if frame is None:
            return None
        return {"frames": [frame], "speed_ms": 0}
    # Multi-frame: each sub-GRH must itself be a valid single-frame entry.
    frames: List[Dict] = []
    for sub_idx, sub_id in enumerate(entry.sub_ids):
        sub_ctx = f"{context} (sub {sub_idx + 1}/{len(entry.sub_ids)} of Grh{grh_id})"
        f = resolve_single_frame(sub_id, grhs, upscaled, missing, sub_ctx)
        if f is None:
            return None
        frames.append(f)
    if not frames:
        missing.append(f"{context}: Grh{grh_id} has zero frames after resolve")
        return None
    return {"frames": frames, "speed_ms": entry.speed_ms}


# ---------------------------------------------------------------------------
# Build catalog dictionaries

def build_body_catalog(
    bodies: Dict[int, Dict],
    grhs: Dict[int, GrhEntry],
    upscaled: set,
    missing: List[str],
) -> Dict[str, Dict]:
    out: Dict[str, Dict] = {}
    for bid in sorted(bodies):
        body = bodies[bid]
        animations: Dict[str, Dict] = {}
        ok = True
        for dir_idx, dir_name in enumerate(DIR_NAMES):
            grh_id = body["walk_grhs"][dir_idx]
            ctx = f"body_{bid} {dir_name} (Walk{dir_idx + 1}=Grh{grh_id})"
            anim = resolve_animation(grh_id, grhs, upscaled, missing, ctx)
            if anim is None:
                missing.append(f"body_{bid}: skipping (missing {dir_name})")
                ok = False
                break
            animations[dir_name] = anim
        if not ok:
            continue
        hox, hoy = body["head_offset"]
        out[f"body_{bid}"] = {
            "head_offset": {"x": hox * 2, "y": hoy * 2},
            "animations": animations,
        }
    return out


def build_dir_catalog(
    raw: Dict[int, List[int]],
    grhs: Dict[int, GrhEntry],
    upscaled: set,
    missing: List[str],
    prefix: str,
) -> Dict[str, Dict]:
    """Generic builder for catalogs that are just 4 directional grh ids per id (heads, helmets, weapons, shields)."""
    out: Dict[str, Dict] = {}
    for cid in sorted(raw):
        animations: Dict[str, Dict] = {}
        ok = True
        for dir_idx, dir_name in enumerate(DIR_NAMES):
            grh_id = raw[cid][dir_idx]
            ctx = f"{prefix}_{cid} {dir_name} (Dir{dir_idx + 1}=Grh{grh_id})"
            anim = resolve_animation(grh_id, grhs, upscaled, missing, ctx)
            if anim is None:
                missing.append(f"{prefix}_{cid}: skipping (missing {dir_name})")
                ok = False
                break
            animations[dir_name] = anim
        if not ok:
            continue
        out[f"{prefix}_{cid}"] = {"animations": animations}
    return out


# ---------------------------------------------------------------------------
# obj.dat -> item icons

def parse_obj_grh_indices(dat_path: Path) -> Dict[int, int]:
    """
    Cucsi obj.dat layout (Windows-1252):
      [OBJ{n}]
      Name=...
      GrhIndex={int}
      ObjType={int}
      ...
    Returns {obj_id -> grh_index}. Skips entries without a GrhIndex.
    """
    sections = parse_ini(dat_path)
    out: Dict[int, int] = {}
    for sec, kv in sections.items():
        m = re.match(r"^OBJ(\d+)$", sec, re.IGNORECASE)
        if not m:
            continue
        obj_id = int(m.group(1))
        if "GrhIndex" not in kv:
            continue
        try:
            grh_id = int(kv["GrhIndex"])
        except ValueError:
            continue
        if grh_id <= 0:
            continue
        out[obj_id] = grh_id
    return out


def build_item_icon_catalog(
    obj_grh_map: Dict[int, int],
    grhs: Dict[int, GrhEntry],
    upscaled: set,
    missing: List[str],
) -> Dict[str, Dict]:
    """
    Each unique GrhIndex referenced by obj.dat -> a single-frame catalog
    entry keyed `item_icon_{grh_id}`. Wire identity is the GRH id (the
    server ships `icon_grh_id` in GROUND_ITEM_SPAWN.item_data).

    Multi-frame Grhs (rare for item icons) -> emit just the first sub-frame.
    Any unresolved Grh -> skip + log to missing_refs.
    """
    out: Dict[str, Dict] = {}
    seen: set = set()
    # Walk obj_ids in ascending order so the YAML ordering is stable.
    for obj_id in sorted(obj_grh_map):
        grh_id = obj_grh_map[obj_id]
        if grh_id in seen:
            continue
        seen.add(grh_id)
        ctx = f"item_icon_{grh_id} (obj.dat[OBJ{obj_id}].GrhIndex)"
        entry = grhs.get(grh_id)
        if entry is None:
            missing.append(f"{ctx}: Grh{grh_id} not in Graficos.ini")
            continue
        if entry.num_frames == 1:
            frame = resolve_single_frame(grh_id, grhs, upscaled, missing, ctx)
        else:
            # Multi-frame icon: take the first sub-frame and treat as static.
            if not entry.sub_ids:
                missing.append(f"{ctx}: Grh{grh_id} multi-frame with empty sub_ids")
                continue
            first_sub = entry.sub_ids[0]
            frame = resolve_single_frame(
                first_sub, grhs, upscaled, missing,
                f"{ctx} (multi-frame, taking first sub Grh{first_sub})",
            )
        if frame is None:
            continue
        out[f"item_icon_{grh_id}"] = {
            "id": grh_id,
            "source": f"Graficos.ini[Grh{grh_id}]",
            "region": frame["region"],
            "file": frame["file"],
        }
    return out


# ---------------------------------------------------------------------------
# Server items.yml verification — every `icon_grh_id` referenced from the
# server catalog must be present in the emitted client catalog.

# Lightweight scanner; we only need icon_grh_id values, not full YAML parse.
_ICON_GRH_RE = re.compile(r"^\s*icon_grh_id:\s*(\d+)\b")


def collect_server_icon_grh_ids(items_yml: Path) -> List[int]:
    """
    Walk the server's items.yml and return every icon_grh_id referenced
    (with duplicates allowed — useful for the "N items reference Grh X"
    diagnostic). Returns [] if the file does not exist; the caller decides
    whether that is fatal.
    """
    if not items_yml.exists():
        return []
    out: List[int] = []
    with open(items_yml, "r", encoding="utf-8") as f:
        for line in f:
            m = _ICON_GRH_RE.match(line)
            if m:
                out.append(int(m.group(1)))
    return out


def verify_server_items_coverage(
    items_catalog: Dict[str, Dict],
    server_grh_ids: List[int],
) -> List[str]:
    """
    Returns a list of human-readable error strings, one per icon_grh_id that
    the server references but the client catalog does not contain. Empty
    list = full coverage.
    """
    present = {entry["id"] for entry in items_catalog.values()}
    errors: List[str] = []
    for grh_id in sorted(set(server_grh_ids)):
        if grh_id not in present:
            errors.append(
                f"server items.yml references icon_grh_id={grh_id} but "
                f"item_icon_{grh_id} is NOT in the emitted client catalog"
            )
    return errors


# ---------------------------------------------------------------------------
# YAML emitter (minimal — keeps ordering, nests dicts/lists, no PyYAML dep)

def _yaml_escape(v) -> str:
    if isinstance(v, str):
        # Filenames / direction keys / etc. — quote conservatively.
        if any(c in v for c in (':', '#', '\n', "'", '"')) or v == "":
            esc = v.replace("\\", "\\\\").replace('"', '\\"')
            return f'"{esc}"'
        # Looks numeric -> quote so YAML doesn't reinterpret.
        try:
            float(v)
            return f'"{v}"'
        except ValueError:
            return v
    if isinstance(v, bool):
        return "true" if v else "false"
    return str(v)


def _emit_yaml(out, value, indent: int = 0) -> None:
    pad = "  " * indent
    if isinstance(value, dict):
        if not value:
            out.write(" {}\n")
            return
        out.write("\n")
        for k, v in value.items():
            if isinstance(v, dict) and v:
                out.write(f"{pad}{k}:")
                _emit_yaml(out, v, indent + 1)
            elif isinstance(v, list) and v and isinstance(v[0], dict):
                out.write(f"{pad}{k}:\n")
                for item in v:
                    out.write(f"{pad}  - ")
                    _emit_inline_dict(out, item)
                    out.write("\n")
            elif isinstance(v, dict) and not v:
                out.write(f"{pad}{k}: {{}}\n")
            else:
                out.write(f"{pad}{k}: {_yaml_inline(v)}\n")
    else:
        out.write(f" {_yaml_inline(value)}\n")


def _emit_inline_dict(out, d: dict) -> None:
    parts = []
    for k, v in d.items():
        if isinstance(v, dict):
            parts.append(f"{k}: {{ {', '.join(f'{kk}: {_yaml_escape(vv)}' for kk, vv in v.items())} }}")
        else:
            parts.append(f"{k}: {_yaml_escape(v)}")
    out.write("{ " + ", ".join(parts) + " }")


def _yaml_inline(v) -> str:
    if isinstance(v, dict):
        return "{ " + ", ".join(f"{k}: {_yaml_escape(vv)}" for k, vv in v.items()) + " }"
    if isinstance(v, list):
        return "[" + ", ".join(_yaml_escape(x) for x in v) + "]"
    return _yaml_escape(v)


def write_yaml(path: Path, data: Dict) -> None:
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        for key, val in data.items():
            f.write(f"{key}:")
            _emit_yaml(f, val, 1)
            f.write("\n")


def write_json(path: Path, data: Dict) -> None:
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, indent=2, sort_keys=False)
        f.write("\n")


# ---------------------------------------------------------------------------
# Main

def main() -> int:
    if not CUCSI_INIT.exists():
        print(f"ERROR: Cucsi Init dir not found: {CUCSI_INIT}", file=sys.stderr)
        print("Cannot parse without source files. Aborting (no partial YAMLs written).", file=sys.stderr)
        return 2
    if not CUCSI_DAT.exists():
        print(f"ERROR: Cucsi Dat dir not found: {CUCSI_DAT}", file=sys.stderr)
        return 2

    required = {
        "Graficos.ini": CUCSI_INIT / "Graficos.ini",
        "obj.dat": CUCSI_DAT / "obj.dat",
        "Personajes.ini": CUCSI_INIT / "Personajes.ini",
        "Cabezas.ini": CUCSI_INIT / "Cabezas.ini",
        "Cascos.ini": CUCSI_INIT / "Cascos.ini",
        "Armas.dat": CUCSI_INIT / "Armas.dat",
        "Escudos.dat": CUCSI_INIT / "Escudos.dat",
        "Fxs.ini": CUCSI_INIT / "Fxs.ini",
    }
    for name, path in required.items():
        if not path.exists():
            print(f"ERROR: missing source file: {path}", file=sys.stderr)
            return 2

    if not UPSCALED_DIR.exists():
        print(f"ERROR: upscaled assets dir not found: {UPSCALED_DIR}", file=sys.stderr)
        return 2

    OUT_DIR.mkdir(parents=True, exist_ok=True)

    print(f"Loading Graficos.ini …", flush=True)
    grhs = load_graficos(required["Graficos.ini"])
    print(f"  -> {len(grhs)} GRH entries indexed")

    print("Indexing assets/upscaled_2x/ …", flush=True)
    upscaled = {p.name for p in UPSCALED_DIR.iterdir() if p.suffix.lower() == ".png"}
    print(f"  -> {len(upscaled)} PNGs available")

    missing: List[str] = []

    print("Parsing Personajes.ini (bodies) …", flush=True)
    bodies_raw = parse_bodies(required["Personajes.ini"])
    bodies = build_body_catalog(bodies_raw, grhs, upscaled, missing)
    print(f"  -> bodies emitted: {len(bodies)} / {len(bodies_raw)}")

    print("Parsing Cabezas.ini (heads) …", flush=True)
    heads_raw = parse_heads_like(
        required["Cabezas.ini"],
        re.compile(r"^HEAD_?(\d+)_?$"),
        ("Head1", "Head2", "Head3", "Head4"),
    )
    heads = build_dir_catalog(heads_raw, grhs, upscaled, missing, "head")
    print(f"  -> heads emitted: {len(heads)} / {len(heads_raw)}")

    print("Parsing Cascos.ini (helmets) …", flush=True)
    helmets_raw = parse_heads_like(
        required["Cascos.ini"],
        re.compile(r"^HEAD_?(\d+)_?$"),
        ("Head1", "Head2", "Head3", "Head4"),
    )
    helmets = build_dir_catalog(helmets_raw, grhs, upscaled, missing, "helmet")
    print(f"  -> helmets emitted: {len(helmets)} / {len(helmets_raw)}")

    print("Parsing Armas.dat (weapons) …", flush=True)
    weapons_raw = parse_heads_like(
        required["Armas.dat"],
        re.compile(r"^Arma(\d+)$", re.IGNORECASE),
        ("Dir1", "Dir2", "Dir3", "Dir4"),
    )
    weapons = build_dir_catalog(weapons_raw, grhs, upscaled, missing, "weapon")
    print(f"  -> weapons emitted: {len(weapons)} / {len(weapons_raw)}")

    print("Parsing Escudos.dat (shields) …", flush=True)
    shields_raw = parse_heads_like(
        required["Escudos.dat"],
        re.compile(r"^ESC(\d+)$", re.IGNORECASE),
        ("Dir1", "Dir2", "Dir3", "Dir4"),
    )
    shields = build_dir_catalog(shields_raw, grhs, upscaled, missing, "shield")
    print(f"  -> shields emitted: {len(shields)} / {len(shields_raw)}")

    print("Parsing Fxs.ini (effects) …", flush=True)
    fxs = parse_fxs(required["Fxs.ini"])
    effects = build_effect_catalog(fxs, grhs, upscaled, missing)
    print(f"  -> effects emitted: {len(effects)} / {len(EFFECT_MAP)}")

    print("Parsing obj.dat (item icons) …", flush=True)
    obj_grh_map = parse_obj_grh_indices(required["obj.dat"])
    items = build_item_icon_catalog(obj_grh_map, grhs, upscaled, missing)
    print(f"  -> items emitted: {len(items)} / {len(set(obj_grh_map.values()))} unique GrhIndex")

    # Write outputs.
    print("Writing YAML + JSON catalogs …", flush=True)
    catalogs = [
        ("bodies", bodies, len(bodies_raw)),
        ("heads", heads, len(heads_raw)),
        ("helmets", helmets, len(helmets_raw)),
        ("weapons", weapons, len(weapons_raw)),
        ("shields", shields, len(shields_raw)),
        ("effects", effects, len(EFFECT_MAP)),
        ("items", items, len(set(obj_grh_map.values()))),
    ]
    for name, data, raw_count in catalogs:
        write_yaml(OUT_DIR / f"{name}.yml", data)
        write_json(OUT_DIR / f"{name}.json", data)

    with open(MISSING_LOG, "w", encoding="utf-8", newline="\n") as f:
        f.write(
            "# Cucsi catalog entries skipped during parse.\n"
            "# Each line is one reason. An entry may produce many lines\n"
            "# (one per missing sub-frame) plus a final 'skipping' line.\n"
            "# Generated by tools/parse_cucsi_graphics.py — do not hand-edit.\n\n"
        )
        for line in missing:
            f.write(line + "\n")

    print()
    print("Summary:")
    for name, data, raw_count in catalogs:
        skipped = raw_count - len(data)
        print(f"  {name}: {len(data)} emitted / {raw_count} parsed  ({skipped} skipped)")
    print(f"  missing log: {MISSING_LOG}")
    print(f"  total skip-log lines: {len(missing)}")

    # Hard-fail if the emitted catalog is missing any icon_grh_id the server
    # actually ships. Prevents the "no sprite_catalog entry for icon_grh_id=X"
    # runtime warning from regressing silently. Skipped only if the server
    # repo isn't checked out next to this client.
    print()
    if not SERVER_ITEMS_YML.exists():
        print(
            f"NOTE: server items.yml not found at {SERVER_ITEMS_YML}; "
            "skipping coverage verification."
        )
        return 0

    server_grh_ids = collect_server_icon_grh_ids(SERVER_ITEMS_YML)
    print(
        f"Verifying server items.yml coverage "
        f"({len(server_grh_ids)} icon_grh_id refs, "
        f"{len(set(server_grh_ids))} unique) …"
    )
    errors = verify_server_items_coverage(items, server_grh_ids)
    if errors:
        print("ERROR: client items catalog does not cover all server references:")
        for line in errors:
            print(f"  {line}")
        return 3
    print("  OK — every server icon_grh_id is present in items catalog.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
