"""Convert Cucsi audio assets into a Godot-friendly tree.

Reads the three Cucsi audio folders (MIDI, WAV, MP3) and produces:

    <out>/music/<n>.ogg     <-- MIDIs rendered via fluidsynth + TimGM6mb.sf2
    <out>/sfx/<n>.wav       <-- WAV copies (Godot 4 supports WAV natively)
    <out>/themes/<n>.mp3    <-- MP3 copies (used for login + character_select themes)

Why fluidsynth: Godot 4 cannot play MIDI natively. We bake to Ogg Vorbis
once at build time. fluidsynth is invoked as a CLI binary (not via the
pyfluidsynth bindings) -- direct file rendering with `-F file.ogg -T oga`
is simpler and avoids one more Python dep on Windows.

Defaults assume the layout already in the repo:

    tools/audio/TimGM6mb.sf2                  (soundfont)
    C:/Tools/fluidsynth/bin/fluidsynth.exe    (Windows binary install)

Pass --fluidsynth / --soundfont to override.

Usage:
    python tools/convert_cucsi_audio.py \\
        --cucsi 'C:/Users/agusp/Documents/Cucsiii/clientecucsi/AUDIO' \\
        --out assets/audio

Failures (a malformed MIDI, a missing input file, etc.) are logged to
stderr and the script continues -- consistent with parse_cucsi_graphics.py.
"""
from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import time
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent

DEFAULT_FLUIDSYNTH = "C:/Tools/fluidsynth/bin/fluidsynth.exe"
DEFAULT_SOUNDFONT = REPO_ROOT / "tools" / "audio" / "TimGM6mb.sf2"
DEFAULT_CUCSI = "C:/Users/agusp/Documents/Cucsiii/clientecucsi/AUDIO"
DEFAULT_OUT = REPO_ROOT / "assets" / "audio"


def render_midi_to_ogg(midi: Path, ogg: Path, fluidsynth: Path, soundfont: Path) -> bool:
    """Render one MIDI to Ogg Vorbis. Returns True on success."""
    cmd = [
        str(fluidsynth),
        "-ni",                  # no interactive shell, no welcome banner
        "-T", "oga",            # Ogg Vorbis container
        "-F", str(ogg),
        "-r", "44100",          # sample rate
        str(soundfont),
        str(midi),
    ]
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=60,
        )
    except subprocess.TimeoutExpired:
        print(f"  TIMEOUT: {midi.name}", file=sys.stderr)
        return False

    if result.returncode != 0:
        print(f"  FAIL ({result.returncode}): {midi.name}", file=sys.stderr)
        if result.stderr:
            print(f"    stderr: {result.stderr.strip()[:200]}", file=sys.stderr)
        return False

    if not ogg.exists() or ogg.stat().st_size == 0:
        print(f"  FAIL (empty output): {midi.name}", file=sys.stderr)
        return False

    return True


def convert_midis(cucsi_root: Path, out_root: Path, fluidsynth: Path, soundfont: Path) -> tuple[int, int]:
    midi_root = cucsi_root / "MIDI"
    out_dir = out_root / "music"
    out_dir.mkdir(parents=True, exist_ok=True)

    midis = sorted(midi_root.glob("*.mid"))
    print(f"[midi] {len(midis)} files in {midi_root}")
    print(f"[midi] -> {out_dir}")

    ok = 0
    fail = 0
    t0 = time.monotonic()
    for i, midi in enumerate(midis, 1):
        ogg = out_dir / (midi.stem + ".ogg")
        if ogg.exists() and ogg.stat().st_size > 0:
            ok += 1
            continue
        if render_midi_to_ogg(midi, ogg, fluidsynth, soundfont):
            ok += 1
        else:
            fail += 1
        if i % 10 == 0 or i == len(midis):
            elapsed = time.monotonic() - t0
            print(f"  [{i}/{len(midis)}] ok={ok} fail={fail} ({elapsed:.1f}s)")

    return ok, fail


def copy_tree(src: Path, dst: Path, ext: str) -> int:
    dst.mkdir(parents=True, exist_ok=True)
    files = sorted(src.glob(f"*.{ext}"))
    n = 0
    for f in files:
        target = dst / f.name
        if target.exists() and target.stat().st_size == f.stat().st_size:
            n += 1
            continue
        shutil.copy2(f, target)
        n += 1
    print(f"[{ext}] {n} files copied -> {dst}")
    return n


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cucsi", default=DEFAULT_CUCSI, help="Cucsi AUDIO folder root (contains MIDI/, WAV/, MP3/)")
    parser.add_argument("--out", default=str(DEFAULT_OUT), help="Output root (default: assets/audio)")
    parser.add_argument("--fluidsynth", default=DEFAULT_FLUIDSYNTH, help="Path to fluidsynth binary")
    parser.add_argument("--soundfont", default=str(DEFAULT_SOUNDFONT), help="Path to .sf2 soundfont")
    args = parser.parse_args()

    cucsi_root = Path(args.cucsi)
    out_root = Path(args.out)
    fluidsynth = Path(args.fluidsynth)
    soundfont = Path(args.soundfont)

    if not cucsi_root.exists():
        print(f"ERROR: --cucsi {cucsi_root} does not exist", file=sys.stderr)
        return 2
    if not fluidsynth.exists():
        print(f"ERROR: --fluidsynth {fluidsynth} does not exist", file=sys.stderr)
        return 2
    if not soundfont.exists():
        print(f"ERROR: --soundfont {soundfont} does not exist", file=sys.stderr)
        return 2

    print(f"== convert_cucsi_audio ==")
    print(f"  cucsi:     {cucsi_root}")
    print(f"  out:       {out_root}")
    print(f"  fluidsynth:{fluidsynth}")
    print(f"  soundfont: {soundfont}")

    ok, fail = convert_midis(cucsi_root, out_root, fluidsynth, soundfont)
    n_wav = copy_tree(cucsi_root / "WAV", out_root / "sfx", "wav")
    n_mp3 = copy_tree(cucsi_root / "MP3", out_root / "themes", "mp3")

    print()
    print(f"DONE: {ok}/{ok + fail} MIDIs -> ogg, {n_wav} WAVs copied, {n_mp3} MP3s copied")
    return 0 if fail == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
