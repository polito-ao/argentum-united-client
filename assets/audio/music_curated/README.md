# Curated music

Hand-authored / hand-rendered music tracks for Argentum United. These are
**original works** — not derived from Cucsi's MIDI library — and are
**tracked in git** so they survive a clean checkout.

The MIDI auto-render path (`tools/convert_cucsi_audio.py --render-midis`)
is the placeholder fallback when a curated track isn't available. The
music director service (future) resolves a `music_id` or context to a
specific file in this folder.

## Tracks

| File | Format | Length | Intended use |
|---|---|---|---|
| `clasica-ao.ogg` | OGG q8 | ~2:22 | TBD — possibly login / character_select / open-world fallback |
| `dragon-ball-sound.ogg` | OGG q8 | ~0:38 | TBD — short, energetic — possibly pre-battle stinger |
| `hobbits.ogg` | OGG q8 | ~2:46 | TBD — peaceful village vibe |
| `ulla.ogg` | OGG q8 | ~1:52 | Ullathorpe city theme (mapa_1) |
| `open-world-day.mp3` | MP3 | — | Open world, daytime hours |
| `open-world-night.mp3` | MP3 | — | Open world, night hours |
| `match-lobby-and-during-siege.mp3` | MP3 | — | Tournament lobby + Castle Siege |

## Looping

OGGs are designed to loop seamlessly — the user crafted them in GarageBand
to flow last-sample → first-sample. To enable in Godot, set
`AudioStreamOggVorbis.loop = true` on the stream resource (or the import
flag). Avoid MP3 for new loop-crafted tracks — encoder padding kills the
seam.

## Source masters

Original WAV / project files are kept locally by the author at
`assets/audio/new-music/`. Those WAVs are gitignored (~30MB each); the
OGGs in this folder are the runtime versions.

## Conversion command

If you re-render a master to OGG:

```
ffmpeg -i input.wav -c:a libvorbis -q:a 8 output.ogg
```

`-q:a 8` is high-quality VBR (~250 kbps), transparent for music. Use `-q:a 6`
(~190 kbps) if you need smaller files at slightly lower fidelity.
