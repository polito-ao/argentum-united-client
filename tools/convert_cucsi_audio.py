"""Convert Cucsi audio assets into a Godot-friendly tree.

Reads the three Cucsi audio folders (MIDI, WAV, MP3) and produces:

    <out>/sfx/<n>.wav       <-- WAVs (PCM verbatim; non-PCM force-converted)
    <out>/themes/<n>.mp3    <-- MP3 copies (used for login + character_select themes)
    <out>/music/<n>.ogg     <-- MIDIs rendered via fluidsynth + FluidR3_GM.sf2
                                (OPT-IN: pass --render-midis to enable)

Music policy (2026-04-27): the rendered-MIDI path is OFF by default. Cucsi's
MIDIs sound generic and don't match the Argentum United identity; the music
direction is hand-curated MP3s dropped in `assets/audio/music_curated/<id>.mp3`.
Pass `--render-midis` if you want quick generic placeholders (e.g. for
prototyping or when you have no curated tracks yet).

Why fluidsynth: Godot 4 cannot play MIDI natively. We bake to Ogg Vorbis
once at build time. fluidsynth is invoked as a CLI binary (not via the
pyfluidsynth bindings) -- direct file rendering with `-F file.ogg -T oga`
is simpler and avoids one more Python dep on Windows.

Why FluidR3_GM: the canonical best-free MIT-licensed General MIDI
soundfont (~140 MB). Replaced TimGM6mb (~6 MB, GPL) on 2026-04-27 --
Tim was thin/tinny on most tracks, FluidR3 ships a fuller orchestra.

Why force-convert non-PCM WAVs: Godot 4's WAV importer accepts only
PCM (s16/s24) and IEEE float. ~25 of the 219 Cucsi SFX are ADPCM /
mu-law / GSM compressed and fail to import. We probe each WAV with
ffprobe and re-encode the compressed ones to pcm_s16le @ 44.1 kHz
via ffmpeg. PCM WAVs are copied as-is (no resample, no quality loss).

Defaults assume the layout already in the repo:

    tools/audio/FluidR3_GM.sf2                (soundfont)
    C:/Tools/fluidsynth/bin/fluidsynth.exe    (Windows binary install)
    ffprobe / ffmpeg on PATH (winget install Gyan.FFmpeg on Windows)

Pass --fluidsynth / --soundfont / --ffmpeg / --ffprobe to override.

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
DEFAULT_SOUNDFONT = REPO_ROOT / "tools" / "audio" / "FluidR3_GM.sf2"
DEFAULT_CUCSI = "C:/Users/agusp/Documents/Cucsiii/clientecucsi/AUDIO"
DEFAULT_OUT = REPO_ROOT / "assets" / "audio"

# Windows winget installs ffmpeg/ffprobe shims here. Python's PATH
# sometimes misses them on a fresh shell, so we look in this canonical
# location too. Override via --ffmpeg / --ffprobe.
WINGET_FFMPEG = Path("C:/Users/agusp/AppData/Local/Microsoft/WinGet/Links/ffmpeg.exe")
WINGET_FFPROBE = Path("C:/Users/agusp/AppData/Local/Microsoft/WinGet/Links/ffprobe.exe")

# Codecs Godot 4 imports without complaint.
PCM_CODECS = {"pcm_s16le", "pcm_s24le", "pcm_s32le", "pcm_f32le", "pcm_u8"}


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
            timeout=120,
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


def probe_codec(wav: Path, ffprobe: Path) -> str | None:
    """Return the audio stream's codec_name (e.g. 'pcm_s16le', 'adpcm_ms')
    or None on probe failure."""
    cmd = [
        str(ffprobe),
        "-v", "error",
        "-select_streams", "a:0",
        "-show_entries", "stream=codec_name",
        "-of", "csv=p=0",
        str(wav),
    ]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
    except subprocess.TimeoutExpired:
        print(f"  PROBE TIMEOUT: {wav.name}", file=sys.stderr)
        return None
    if result.returncode != 0:
        print(f"  PROBE FAIL: {wav.name} -> {result.stderr.strip()[:120]}", file=sys.stderr)
        return None
    codec = result.stdout.strip()
    return codec or None


def transcode_to_pcm(src: Path, dst: Path, ffmpeg: Path) -> bool:
    """Force-convert a non-PCM WAV to pcm_s16le @ 44.1 kHz."""
    cmd = [
        str(ffmpeg),
        "-y",                    # overwrite
        "-loglevel", "error",
        "-i", str(src),
        "-acodec", "pcm_s16le",
        "-ar", "44100",
        str(dst),
    ]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
    except subprocess.TimeoutExpired:
        print(f"  TRANSCODE TIMEOUT: {src.name}", file=sys.stderr)
        return False
    if result.returncode != 0:
        print(f"  TRANSCODE FAIL: {src.name} -> {result.stderr.strip()[:200]}", file=sys.stderr)
        return False
    return dst.exists() and dst.stat().st_size > 0


def convert_wavs(cucsi_root: Path, out_root: Path, ffprobe: Path, ffmpeg: Path) -> tuple[int, list[str]]:
    """Copy PCM WAVs verbatim; force-convert anything else.

    Returns (count, list of force-converted filenames)."""
    src_dir = cucsi_root / "WAV"
    dst_dir = out_root / "sfx"
    dst_dir.mkdir(parents=True, exist_ok=True)

    files = sorted(src_dir.glob("*.wav"))
    print(f"[wav] {len(files)} files in {src_dir}")
    print(f"[wav] -> {dst_dir}")

    forced: list[str] = []
    n = 0
    for src in files:
        dst = dst_dir / src.name
        codec = probe_codec(src, ffprobe)
        if codec is None:
            # Probe failed — fall back to a copy and let Godot complain
            # if it must.
            shutil.copy2(src, dst)
            n += 1
            continue
        if codec in PCM_CODECS:
            # Already PCM; copy as-is.
            if not (dst.exists() and dst.stat().st_size == src.stat().st_size):
                shutil.copy2(src, dst)
            n += 1
            continue
        # Compressed (ADPCM / mu-law / GSM / etc.) — Godot rejects.
        # Force-transcode to pcm_s16le.
        print(f"  FORCE PCM: {src.name} (was {codec})")
        if transcode_to_pcm(src, dst, ffmpeg):
            forced.append(f"{src.stem} ({codec} -> pcm_s16le)")
            n += 1
        else:
            # Last resort: copy raw so the count stays sensible; log already emitted.
            shutil.copy2(src, dst)
            n += 1

    print(f"[wav] {n} files -> sfx ({len(forced)} force-converted to PCM)")
    return n, forced


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


def resolve_tool(cli_value: str | None, *fallbacks: Path) -> Path | None:
    """Return the first existing path among (cli_value, *fallbacks, PATH lookup)."""
    if cli_value:
        p = Path(cli_value)
        if p.exists():
            return p
    for fb in fallbacks:
        if fb.exists():
            return fb
    # PATH lookup as a last resort.
    candidate = shutil.which(fallbacks[0].stem if fallbacks else "")
    return Path(candidate) if candidate else None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cucsi", default=DEFAULT_CUCSI, help="Cucsi AUDIO folder root (contains MIDI/, WAV/, MP3/)")
    parser.add_argument("--out", default=str(DEFAULT_OUT), help="Output root (default: assets/audio)")
    parser.add_argument("--fluidsynth", default=DEFAULT_FLUIDSYNTH, help="Path to fluidsynth binary")
    parser.add_argument("--soundfont", default=str(DEFAULT_SOUNDFONT), help="Path to .sf2 soundfont")
    parser.add_argument("--ffprobe", default=None, help="Path to ffprobe binary")
    parser.add_argument("--ffmpeg", default=None, help="Path to ffmpeg binary")
    parser.add_argument(
        "--render-midis",
        action="store_true",
        default=False,
        help=(
            "Opt in to rendering Cucsi MIDIs to Ogg Vorbis (off by default). "
            "Music is hand-curated via assets/audio/music_curated/; this "
            "fallback is for placeholders only."
        ),
    )
    args = parser.parse_args()

    cucsi_root = Path(args.cucsi)
    out_root = Path(args.out)
    soundfont = Path(args.soundfont)

    ffprobe = resolve_tool(args.ffprobe, WINGET_FFPROBE)
    ffmpeg = resolve_tool(args.ffmpeg, WINGET_FFMPEG)

    if not cucsi_root.exists():
        print(f"ERROR: --cucsi {cucsi_root} does not exist", file=sys.stderr)
        return 2
    # MIDI tooling is only required when --render-midis is set. WAV + MP3
    # conversion needs only ffmpeg/ffprobe.
    fluidsynth: Path | None = None
    if args.render_midis:
        fluidsynth = Path(args.fluidsynth)
        if not fluidsynth.exists():
            print(f"ERROR: --fluidsynth {fluidsynth} does not exist", file=sys.stderr)
            return 2
        if not soundfont.exists():
            print(f"ERROR: --soundfont {soundfont} does not exist", file=sys.stderr)
            return 2
    if ffprobe is None or not ffprobe.exists():
        print("ERROR: ffprobe not found. Install ffmpeg (Windows: `winget install Gyan.FFmpeg`)", file=sys.stderr)
        return 2
    if ffmpeg is None or not ffmpeg.exists():
        print("ERROR: ffmpeg not found. Install ffmpeg (Windows: `winget install Gyan.FFmpeg`)", file=sys.stderr)
        return 2

    print(f"== convert_cucsi_audio ==")
    print(f"  cucsi:        {cucsi_root}")
    print(f"  out:          {out_root}")
    print(f"  ffprobe:      {ffprobe}")
    print(f"  ffmpeg:       {ffmpeg}")
    print(f"  render-midis: {args.render_midis}")
    if args.render_midis:
        print(f"  fluidsynth:   {fluidsynth}")
        print(f"  soundfont:    {soundfont}")

    ok = fail = 0
    if args.render_midis:
        ok, fail = convert_midis(cucsi_root, out_root, fluidsynth, soundfont)
    else:
        print("[midi] SKIPPED (use --render-midis to enable). "
              "Music: drop curated MP3s in assets/audio/music_curated/<id>.mp3.")
    n_wav, forced = convert_wavs(cucsi_root, out_root, ffprobe, ffmpeg)
    n_mp3 = copy_tree(cucsi_root / "MP3", out_root / "themes", "mp3")

    print()
    if args.render_midis:
        print(f"DONE: {ok}/{ok + fail} MIDIs -> ogg, {n_wav} WAVs -> sfx, {n_mp3} MP3s -> themes")
    else:
        print(f"DONE: MIDI render skipped, {n_wav} WAVs -> sfx, {n_mp3} MP3s -> themes")
    if forced:
        print(f"Force-converted to PCM ({len(forced)}):")
        for entry in forced:
            print(f"  - {entry}")
    return 0 if fail == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
