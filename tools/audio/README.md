# Audio toolchain

This folder holds the offline tools and bundled assets needed to convert
Cucsi's audio (MIDI / WAV / MP3) into Godot-friendly streams. The audio
output itself lands in `assets/audio/` and is **not** committed (same
pattern as `assets/upscaled_2x/`). New devs run the conversion locally.

## Contents

- `FluidR3_GM.sf2` — **Default General MIDI soundfont.** ~140 MB.
  Frank Wen's canonical free GM soundfont — fuller, richer instruments
  than TimGM6mb.
  - **Source**: https://musical-artifacts.com/artifacts/738
  - **License**: MIT (Frank Wen 2000-2002, 2008; Toby Smithe 2008).
    String embedded in the SF2 header reads "Licensed under the MIT
    License." The soundfont is referenced by the build script — no
    rendered audio is redistributed under our license, only generated
    locally per dev.
  - Mirror: https://archive.org/download/fluidr3-gm/FluidR3_GM.sf2

- `TimGM6mb.sf2` — **Deprecated.** Tim Brechbill's compact GM soundfont
  (~6 MB, GPL-2.0). Was the default through 2026-04-25; replaced by
  FluidR3_GM because Tim sounds thin/tinny on most Cucsi MIDIs. Kept
  documented (not bundled) for anyone who wants to A/B or who can't
  spare the FluidR3 download.
  - Source: https://sourceforge.net/p/mscore/code/HEAD/tree/trunk/mscore/share/sound/TimGM6mb.sf2
  - Pass `--soundfont tools/audio/TimGM6mb.sf2` to fall back.

## Prerequisites

- Python 3.10+ (already required for `parse_cucsi_graphics.py` etc.)
- fluidsynth 2.4.x as a CLI binary
  - **Windows**: download the `winXX-x64` zip from
    https://github.com/FluidSynth/fluidsynth/releases and extract
    somewhere on PATH (or pass `--fluidsynth` to the script). The
    repo currently expects `C:/Tools/fluidsynth/bin/fluidsynth.exe`.
  - macOS: `brew install fluid-synth`
  - Linux: `apt install fluidsynth`
- ffmpeg + ffprobe — needed to detect non-PCM WAVs (a chunk of Cucsi's
  SFX library is ADPCM / mu-law / GSM, which Godot 4 cannot import)
  and force-convert them to `pcm_s16le`.
  - **Windows**: `winget install Gyan.FFmpeg` (installs to
    `C:/Users/<you>/AppData/Local/Microsoft/WinGet/Links/`, which the
    script auto-detects), or download from https://ffmpeg.org/download.html.
  - macOS: `brew install ffmpeg`
  - Linux: `apt install ffmpeg`

The script requires CLI binaries; no Python audio bindings. Direct
file rendering via `fluidsynth -F file.ogg` and `ffmpeg -i src dst`
is simpler and matches the `parse_cucsi_graphics.py` "shell out, log,
move on" pattern.

## Running the conversion

From the repo root:

```bash
python tools/convert_cucsi_audio.py \
    --cucsi 'C:/Users/agusp/Documents/Cucsiii/clientecucsi/AUDIO' \
    --out assets/audio
```

This script:

1. Renders every `.mid` from `Cucsi/AUDIO/MIDI/` to `assets/audio/music/<n>.ogg`
   via fluidsynth + FluidR3_GM.sf2 (Ogg Vorbis, 44.1 kHz stereo).
2. Probes every `.wav` from `Cucsi/AUDIO/WAV/` with ffprobe; PCM ones
   are copied verbatim to `assets/audio/sfx/`, anything else (ADPCM /
   mu-law / GSM / ...) is force-converted to `pcm_s16le @ 44.1 kHz`
   via ffmpeg. Each force-conversion is logged.
3. Copies every `.mp3` from `Cucsi/AUDIO/MP3/` into `assets/audio/themes/`
   verbatim.

Total runtime: ~5-8 minutes (FluidR3 is heavier than Tim). Total
output: ~400-500 MB (the 112 Ogg music files dominate). Failed MIDIs
(rare) are logged and skipped.

## Why this lives here, not on disk-image

We keep the toolchain in-repo so any contributor can reproduce the
asset tree without external instructions. The rendered output is
gitignored and lives in Google Drive (alongside `assets/upscaled_2x/`)
for devs who want to skip the local render step.
