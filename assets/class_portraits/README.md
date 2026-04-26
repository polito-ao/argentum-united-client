# Class Portraits

Static portrait artwork for the 7 MVP classes. Used by the FIFA-style character
cards on the character-select screen (wired in PR
`character-select-fifa-cards`).

## Files

7 JPEG portraits, all 167 x 210 px, ~18-21 KB each:

| File | Class |
|---|---|
| `mago.jpg` | Mago |
| `bardo.jpg` | Bardo |
| `clerigo.jpg` | Clerigo |
| `paladin.jpg` | Paladin |
| `asesino.jpg` | Asesino |
| `cazador.jpg` | Cazador |
| `guerrero.jpg` | Guerrero |

## Source & licensing

- **Source**: project reference wiki at https://cucsi-ao-wiki.vercel.app/
  (under `assets/` with content-hashed filenames).
- **License**: original Argentum Online community art. The wiki is maintained
  by this project's owner, who has explicit permission to use these portraits
  in `argentum-united`.
- **Note**: filenames on the wiki are content-hashed (e.g. `Mag-lnXvupa7.jpg`).
  Files in this directory are renamed to stable class slugs so client code can
  reference them without churn when the wiki rebuilds.

## Re-downloading

If portraits ever need to be regenerated, the download URLs are listed in the
PR that introduced this directory (`class-portraits-and-asset-prompts`).
