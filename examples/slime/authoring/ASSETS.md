# Sample asset pipeline

Run from the Godot repository root:

```powershell
python examples/slime/tools/build_assets.py --cli ../Gaussian-Cake/build/Release/gc_cli.exe
python examples/slime/tools/build_assets.py --validate-only
```

The geometry implementation in `model_geometry.py` is a snapshot of the approved
model generator. It uses only Python's standard library and is self-contained.
All five models have round, mouthless eyes. Static geometry, colored Gaussian
PLY sources, morph GLBs, color lookup PNGs, GCSPLAT clips and `.gcproject` files
are reproducible. This directory is ignored by Godot's asset scanner.

The sample GLBs use deterministic, authored correspondence rather than asking
the general-purpose mesh fitter to rediscover the existing shared topology.
Body vertices and both eyes correspond exactly. Extra target detail geometry
(apple stem/leaf and crate rails) starts as tiny triangles inside the slime body
and grows continuously into its target. Each GLB has a native `Morph` animation
and one position/normal blend shape, lasting 0.75 seconds. The shader interpolates
linear COLOR_0 to the target's sRGB color lookup PNG using its provided UVs.
These sample-specific color transitions are not a new general GLB exporter feature.

The Gaussian Cake CLI bakes the actual Gaussian transitions using 48,000 source
surface Gaussians, 16 FPS and 0.75 seconds: 13 frames, 34,944,116 bytes per morph.
Each of the four files can be sought forward or backward by the existing addon.
Gaussian timing is linear with no wave, mid-growth, cohesion, or area stretch;
the sample controller can apply a common smoothstep to both rendering modes.
The topology and Gaussian correspondence algorithms are different, so their
intermediate shapes can differ even though the endpoints reproduce the same art.

`assets/manifest.json` contains `forms` and `transitions` dictionaries keyed by
form name. Each form has `static_scene`, `static_splat`, `center`, `scale`, and
`triangles`. Each transition has `glb`, `splat`, `color_texture`, `duration` and
`vertices`. Paths are portable `res://examples/slime/...` references.

Gaussian Cake centers and scales each PLY independently. Restore a rendered
splat's position using `form.center`, and its uniform scale using `form.scale`.
During a morph, interpolate both transforms between slime and the target with
the same normalized progress passed to `seek(duration * progress)`. The GLBs
already use the original authored coordinates, +Y up, +Z front, feet near y=0.

All splat clips start with the identical slime point set. Target IDs can be
permuted during matching, so switching clips should happen only at the slime
endpoint. Validation allows quaternion normalization roundoff below 1e-6 and
checks exact decorated GLB target geometry and the target Gaussian surface set.
No full-resolution meshes are swapped in during the animation.
