# Audio assets

The contents of this folder are **not committed** (see `.gitignore`).
Same pattern as `assets/upscaled_2x/`: large binary blobs sourced from a
deterministic build pipeline live elsewhere (Google Drive mirror) and
are reproducible locally from Cucsi via the conversion tool.

## Layout

```
assets/audio/
  sfx/             <id>.wav     Sound effects, copied from Cucsi WAV/ verbatim (219 files)
  themes/          <id>.mp3     UI / menu themes (login, character select, etc.) (11 files)
  music_curated/   <id>.mp3     Hand-curated music tracks (commit-friendly, the
                                canonical music source going forward)
  music/           <id>.ogg     OPTIONAL: rendered Cucsi MIDIs — only present if
                                you ran `convert_cucsi_audio.py --render-midis`.
                                Generic placeholders, gitignored.
```

The `<id>` matches Cucsi's numbering — the numeric ID is the wire
identity used by the server's `PLAY_SFX` / `MUSIC_CHANGE` packets.

## Music policy

**Hand-curated MP3s only.** Drop user-curated tracks in
`assets/audio/music_curated/<id>.mp3`. The Cucsi MIDI render fallback
(`--render-midis`) is opt-in for placeholder use only — generic and
not on-brand.

Cucsi's 11 MP3 themes in `assets/audio/themes/` are kept as-is — they
are high-quality pre-exports already curated by Cucsi.

If you previously ran the script in MIDI-render mode, the resulting
`assets/audio/music/*.ogg` is still picked up by the in-game
AudioPlayer (it's gitignored, so it doesn't pollute commits). Wipe
manually with `rm -rf assets/audio/music/` if you want a clean slate.

## How to populate

### Option A: regenerate from Cucsi (recommended for devs with Cucsi installed)

```bash
python tools/convert_cucsi_audio.py
```

Run from the repo root. Reads `C:/Users/agusp/Documents/Cucsiii/clientecucsi/AUDIO/`
by default; pass `--cucsi <path>` if your Cucsi tree lives elsewhere.

Default mode just processes WAVs + MP3s. Requires ffmpeg / ffprobe
(Windows: `winget install Gyan.FFmpeg`). The ffmpeg toolchain is used
to detect non-PCM WAVs (a chunk of Cucsi's SFX library is ADPCM /
mu-law / GSM) and force-convert them to `pcm_s16le` so Godot can
import them.

Pass `--render-midis` to additionally render Cucsi's MIDIs to Ogg
Vorbis under `assets/audio/music/`. That path also needs fluidsynth
(Windows binary downloaded from
https://github.com/FluidSynth/fluidsynth/releases — see
`tools/audio/README.md` for full install notes) and the
`tools/audio/FluidR3_GM.sf2` soundfont (MIT, ~140 MB).

Default-mode runtime: ~30-60 seconds. Output ~30-50 MB.
With `--render-midis`: add ~5-8 minutes and ~350 MB of Ogg music.

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
