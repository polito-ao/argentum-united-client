# Audio assets

The contents of this folder are **not committed** (see `.gitignore`).
Same pattern as `assets/upscaled_2x/`: large binary blobs sourced from a
deterministic build pipeline live elsewhere (Google Drive mirror) and
are reproducible locally from Cucsi via the conversion tool.

## Layout

```
assets/audio/
  music/   <id>.ogg     Background MIDI tracks rendered to Ogg Vorbis (112 files)
  sfx/     <id>.wav     Sound effects, copied from Cucsi WAV/ verbatim (219 files)
  themes/  <id>.mp3     UI / menu themes (login, character select, etc.) (11 files)
```

The `<id>` matches Cucsi's numbering — the numeric ID is the wire
identity used by the server's `PLAY_SFX` / `MUSIC_CHANGE` packets.

## How to populate

### Option A: regenerate from Cucsi (recommended for devs with Cucsi installed)

```bash
python tools/convert_cucsi_audio.py
```

Run from the repo root. Reads `C:/Users/agusp/Documents/Cucsiii/clientecucsi/AUDIO/`
by default; pass `--cucsi <path>` if your Cucsi tree lives elsewhere.

Requires fluidsynth (Windows binary downloaded from
https://github.com/FluidSynth/fluidsynth/releases — see
`tools/audio/README.md` for full install notes) plus the bundled
`tools/audio/TimGM6mb.sf2` soundfont (GPL-2.0).

Total runtime: ~3-5 minutes. Output ~400 MB.

### Option B: pull from Google Drive

If you don't have Cucsi locally, grab the latest tarball from the team
drive and unpack into this directory.

## Why not commit the audio?

- 400 MB total — too big for git
- The MIDI -> OGG render is deterministic given the same fluidsynth
  version and soundfont; reproducible builds beat tracked binaries
- WAVs and MP3s are 1:1 copies from the Cucsi distribution; no
  transformation, no need to version separately
- Mirrors the `assets/upscaled_2x/` workflow already in CLAUDE.md
