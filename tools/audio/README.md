# Audio toolchain

This folder holds the offline tools and bundled assets needed to convert
Cucsi's audio (MIDI / WAV / MP3) into Godot-friendly streams. The audio
output itself lands in `assets/audio/` and is **not** committed (same
pattern as `assets/upscaled_2x/`). New devs run the conversion locally.

## Contents

- `TimGM6mb.sf2` — General MIDI soundfont used by fluidsynth to render
  the 112 Cucsi `.mid` background tracks into Ogg Vorbis. ~6 MB.
  - **Source**: https://sourceforge.net/p/mscore/code/HEAD/tree/trunk/mscore/share/sound/TimGM6mb.sf2
  - **License**: GPL-2.0 (Tim Brechbill, 2004). The soundfont lives in
    this repo only as a build dependency for the conversion script —
    no rendered audio is redistributed under our license, only generated
    locally per dev.
  - Mirror: https://musical-artifacts.com/artifacts/802

## Prerequisites

- Python 3.10+ (already required for `parse_cucsi_graphics.py` etc.)
- fluidsynth 2.4.x as a CLI binary
  - **Windows**: download the `winXX-x64` zip from
    https://github.com/FluidSynth/fluidsynth/releases and extract
    somewhere on PATH (or pass `--fluidsynth` to the script). The
    repo currently expects `C:/Tools/fluidsynth/bin/fluidsynth.exe`.
  - macOS: `brew install fluid-synth`
  - Linux: `apt install fluidsynth`

The script requires a CLI binary; `pyfluidsynth` is **not** used because
direct file rendering via `fluidsynth -F file.ogg` is simpler and matches
the `parse_cucsi_graphics.py` "shell out, log, move on" pattern.

## Running the conversion

From the repo root:

```bash
python tools/convert_cucsi_audio.py \
    --cucsi 'C:/Users/agusp/Documents/Cucsiii/clientecucsi/AUDIO' \
    --out assets/audio
```

This script:

1. Renders every `.mid` from `Cucsi/AUDIO/MIDI/` to `assets/audio/music/<n>.ogg`
   via fluidsynth + TimGM6mb.sf2 (Ogg Vorbis, 44.1 kHz stereo).
2. Copies every `.wav` from `Cucsi/AUDIO/WAV/` into `assets/audio/sfx/`
   verbatim.
3. Copies every `.mp3` from `Cucsi/AUDIO/MP3/` into `assets/audio/themes/`
   verbatim.

Total runtime: ~3-5 minutes. Total output: ~400 MB (the 112 Ogg music
files dominate). Failed MIDIs (rare) are logged and skipped.

## Why this lives here, not on disk-image

We keep the toolchain in-repo so any contributor can reproduce the
asset tree without external instructions. The rendered output is
gitignored and lives in Google Drive (alongside `assets/upscaled_2x/`)
for devs who want to skip the local render step.
