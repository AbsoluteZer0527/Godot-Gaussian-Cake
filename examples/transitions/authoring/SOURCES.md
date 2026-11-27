# Complex scene source preparation

The showcase uses a local cactus capture and two complete procedural scenes
from the user's `SyntaxSplat-main` reference. Generated files stay in ignored
`out/complex-sources/`; the scripts do not change the originals.

| Scene | Source | Full splat count | PLY bytes |
|---|---|---:|---:|
| Cactus | `meshes/cactus_splat3_30kSteps_142k_splats.ply` | 139,410 | 7,807,322 |
| Lighthouse island | SyntaxSplat `scenes/island.js` | 202,356 | 11,332,298 |
| Coral reef | SyntaxSplat `scenes/reef.js` | 344,405 | 19,287,042 |

## Generate the procedural scenes

Requirements: Node.js 20+ and the supplied SyntaxSplat source directory. The
generator imports the original SDF sampling, lighting and PLY exporter; it
does not approximate these scenes with substitute geometry. It evaluates the
rig at rest (`t=0`) and writes a standard binary little-endian 3DGS PLY.

Prepare a local copy of the pinned three.js dependency (the original browser
wrapper imports an HTTPS URL, which Node cannot import directly):

```powershell
New-Item -ItemType Directory -Force out/syntax-complex-work
Invoke-WebRequest -Uri 'https://cdn.jsdelivr.net/npm/three@0.160.0/build/three.module.js' -OutFile out/syntax-complex-work/three.js
Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/mrdoob/three.js/r160/LICENSE' -OutFile out/syntax-complex-work/THREE-LICENSE
node tools/generate_complex_splats.mjs --reference 'C:/Users/zhulu/Downloads/SyntaxSplat-main/SyntaxSplat-main' --scene island --workers 6
node tools/generate_complex_splats.mjs --reference 'C:/Users/zhulu/Downloads/SyntaxSplat-main/SyntaxSplat-main' --scene reef --workers 6
```

Replace `--reference` with the path to your copy. The minimum original files
are `engine.js`, `export.js`, `LICENSE`, and `scenes/<scene>.js`; they are copied
to the working directory. Supply an already downloaded dependency with
`--three <path>` if needed. The three.js revision is checked before baking.

`--size 1.8` matches the source's default splat-size setting. `--plan 1` reports
counts without sampling. Full scene budgets are used by default; optional
`--budget N` allocates a smaller count proportionally across parts. Fixed
per-chunk seeds and ordered result assembly make the PLY independent of worker
completion order. The island export was verified byte-identical with two and
six workers.

Each scene also produces JSON containing its camera, palette, part counts,
bounds, source hashes and output hash. `<scene>.parts.u32` is a little-endian
uint32 part ID for every PLY record. Both scenes are right-handed, +Y up.
The reef includes low-opacity shafts and motes, so its full bounds extend
beyond the solid coral. Pixel palette quantization and dynamic browser effects
are rendering steps, not baked into the standard PLY.

## Prepare the local cactus

```powershell
python tools/prepare_cactus.py
```

The standard-library-only script reads the smallest supplied cactus capture,
rotates it 180 degrees around X into the same +Y-up convention and writes
`out/complex-sources/cactus.ply`. Positions become `(x, -y, -z)` and WXYZ
quaternions become `(-x, w, -z, y)`. Units, splat scales, opacity and DC color
are preserved, with unchanged float32 fields copied bit for bit. The 45
higher-order spherical-harmonic fields are explicitly removed for the
showcase's DC-only playback profile. The original file is never rewritten.

The original SHA256 is
`95ba6aeb2825674814543d930c1a7e1c65bbabd57a735a669ae71ca24178e1e5`.
The derived SHA256 is
`974c1a2b3fccaa0e7a98f751833866227c436e63dff5a3f1570d7392709bad83`.
Paths, hashes, orientation changes and discarded attributes are also recorded
in `cactus.json`.

## Attribution and redistribution

SyntaxSplat's supplied `LICENSE` is MIT, copyright (c) 2026 iamvillain. The
generator copies it verbatim as `SYNTAXSPLAT-LICENSE` beside the generated
assets. three.js 0.160.0 is MIT, copyright 2010–2023 three.js authors; retain
`THREE-LICENSE` when distributing the dependency. Both licenses are retained
in the working directory as well.

The cactus is a user-provided local capture. Its supplied files contain no
source URL or license; no MIT license is inferred for it. Keep that provenance
distinct from the two MIT procedural scenes when publishing source assets.
