# Complex scene transitions

Open `showcase.tscn` in Godot 4.7.2 and press **F6**. **F5** runs the project's
configured main scene. The gallery, camera, viewport and controls are an editable
node tree; `showcase.gd` wires their behavior. Command-line capture and benchmark
helpers live separately in `showcase_automation.gd`.

- Choose source and destination, then **Morph / restart**. Duration defaults to four seconds.
- **Space** plays/pauses. Drag the progress slider to hold any intermediate pose.
- **B** compares shared-reference correspondence with a refined pair map. It restarts
  the selected pair at the same progress and canonical starting pose for a fair comparison.
- **P** switches raw Gaussian colors and the pixel treatment: a smaller viewport,
  nearest enlargement, ordered dithering and a stable 72-color palette. This includes
  both SyntaxSplat source palettes and twelve colors sampled from the cactus.
- Drag the scene to orbit; wheel to zoom. **Auto cycle** carries the current splat
  identities through cactus → island → reef → cactus without resetting at endpoints.

The three endpoints each contain **48,000 Gaussians**, including rotations, scales,
colors and opacity. The reef and island come from the supplied MIT-licensed
SyntaxSplat scene definitions, baked at a fixed rest pose. The cactus is the local
capture, converted to Y-up and view-independent DC color. These are source-derived
3D Gaussian assets, not generated concept images. Read [authoring/SOURCES.md](authoring/SOURCES.md)
for exact provenance, licenses and transformations.

## Preparation and runtime

`authoring/complex.gcformproject` and its relative PLY paths can be opened by the
Gaussian Cake authoring tool. Rebuild from that tool's checkout with:

```powershell
gc_cli forms path/to/authoring/complex.gcformproject --output path/to/assets
gc_cli refine-forms path/to/assets/library.json --pairs cactus:island,island:reef,reef:cactus --color-weight 0.35 --passes 8 --neighbors 24
```

Use `gc_cli --help` for the exact supported CLI options in your version.
The prepared assets are already included, so running this scene needs neither the
authoring application nor Python/Node/native extensions. `authoring/.gdignore`
and the export preset exclude source PLYs and sidecar metadata from the game.

`assets/forms.gcforms` stores three endpoints (about 8.06 MB). Six `.gcmap` files
store the forward/inverse pair permutations (192,032 bytes each). The runtime
uploads source/destination data when a transition begins; each frame changes the
interpolation amount and updates transparency order. No intermediate animation
frames are baked. Shared mode works for unprepared pairs; pair maps are optional.

The measured objective combines spatial and color mismatch. The gallery shows
the authored before/after cost and spatial RMS/P95. Refinement improves that
objective while preserving each endpoint's exact splat set; it does not guarantee
globally optimal transport, semantic part matching, or the prettiest intermediate
shape. Mid-transition redirection freezes the current pose and uses stable IDs,
since the arbitrary blended pose has no authored pair map. It preserves pose,
not velocity. Splat sorting and overdraw remain runtime work.

## Validation and measurements

`tests/transport_maps_test.gd` covers corrupt headers/payloads, bijections,
forward/inverse pairs, splat-only loading, nonidentity cycle composition, exact
endpoint attributes and interrupted-pose continuity. Existing topology/slime,
lifecycle, pixel and sorting suites also remain passing. The Desktop PCK preset
includes the two JSON files and the imported maps as normal Godot resources.

On the RTX 5070 Laptop GPU, Compatibility renderer, 1100×720 window, vsync off,
island → reef over four seconds after warm-up:

| Presentation | Correspondence | Mean frame | P95 frame | FPS | Endpoint setup |
|---|---|---:|---:|---:|---:|
| Pixel | Shared | 9.86 ms | 11.03 ms | 101.4 | 28.2 ms |
| Pixel | Refined | 10.23 ms | 11.39 ms | 97.7 | 57.3 ms |
| Raw | Shared | 9.58 ms | 10.68 ms | 104.3 | 29.4 ms |
| Raw | Refined | 9.81 ms | 11.00 ms | 102.0 | 57.5 ms |

These are local observations, not minimum hardware guarantees. Frame times exclude
asset loading and endpoint preparation; setup is reported separately. Refinement
targets travel quality, not a higher frame rate. Reproduce with:

```powershell
godot --path . res://examples/transitions/showcase.tscn -- --transition-benchmark --transition-mode=refined
```

Add `--transition-raw` for raw presentation or use `--transition-mode=shared`.
JSON measurements save in `out/transitions/`. Automated visual capture:

```powershell
godot --path . res://examples/transitions/showcase.tscn -- --transition-capture --transition-from=island --transition-to=reef --transition-progress=0.5
```

For a rest endpoint, use the same source/destination and progress 1. Captures warm
the renderer first and save PNGs under `out/transitions/`. `--transition-smoke`
exercises the same route without capturing. `--expect-pack` additionally verifies
that all six map resources load without raw source maps or editor importer scripts.
