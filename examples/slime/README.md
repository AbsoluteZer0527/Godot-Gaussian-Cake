# Slime playground sample

Open `examples/slime/playground.tscn` in Godot and press **F6**. Walk the slime
into a mushroom, stone, apple, or crate to become that item. Transitions last
**1.5 seconds** by default and go directly from the current shape to the target.
Apple can become mushroom without passing through slime. You can keep walking
while morphing; touching another item redirects the morph from its current pose.

- **WASD / arrows:** move relative to the camera; the character turns toward travel.
- **Right mouse drag / Q and E:** orbit the following third-person camera.
- **Mouse wheel:** zoom.
- **R:** morph back to slime.
- **M:** switch topology / Gaussian splat rendering, preserving transition progress.
- **P:** compare the pixel presentation with the raw render.

Select **Player** in the editor to change `morph_duration`. This changes the
runtime clock; it does not rebake an animation or add exported frames. A target
activates when entered, rather than repeatedly while the player remains inside.
The fixed gameplay collider is independent of visible shape, rotation, and morph.

## Reusable forms

The editable scene contains the stage, camera, player, target `Area3D` nodes and
HUD. **Player / VisualRoot / Forms** uses the addon's reusable form player and
loads `assets/forms/library.json`. Both modes share one destination and clock.

The library stores five named endpoints, not a clip for every pair:

- `forms.glb`: one mesh with **7,272 shared vertices** and four named blend shapes.
  Body and eye vertices retain their identities. Apple and crate accessories have
  permanent slots that collapse inside forms where they are absent.
- `form_colors.png`: linear RGB vertex appearance for all five forms, selected
  with the same weights as the shape. Ordinary GLB blend shapes do not animate
  vertex colors, so the addon applies the supplied appearance atlas.
- `forms.gcforms`: **48,000 Gaussians per form** in common object-local coordinates.
  Positions, quaternion rotation, logarithmic scale, linear color and opacity
  are interpolated at runtime. The payload is about **13.4 MB** for all five
  endpoints; the former four sampled transition payloads total about 140 MB.

When a destination changes during a morph, the addon takes the currently
interpolated pose as the new start. This preserves pose continuity; it does not
promise continuous velocity through arbitrary interruptions. A common mapping
permits any pair, but it is not an individually optimized transport solve for
that pair. Complex baked animation clips remain supported by the other addon
players.

Stationary touch targets remain mesh models; the 48,000-splat budget belongs to
the active character. The splat renderer retains cached endpoint positions,
native packed depth sorting and its compact GPU order texture. The library is
prepared once, and normal transitions do not load a separate animated clip.

## Pixel presentation

The world uses a low-resolution viewport, curated 40-color palette and a 4x4
ordered dither, enlarged by an integer scale with nearest filtering. HUD and item
names remain at native resolution. This follows the palette/dither approach of
the local SyntaxSplat reference; it is not a port of its part-ID/depth outlines.

Select the playground root to adjust `pixel_rows`, `dither_amount`, and the
palette. **P** disables palette/dither and resolution reduction for comparison.
The authored shading is baked; neither mode adds dynamic jelly translucency,
relighting, deforming collision geometry, or shadow casting.

## Rebuild and verify

Normal playback needs only this repository and Godot. Rebuilding requires the
Gaussian Cake CLI from the authoring-tool repository:

```powershell
python examples/slime/tools/build_form_library.py --cli ../Gaussian-Cake/build/Release/gc_cli.exe
```

The script writes an editable `authoring/forms/slime.gcformproject` and prepared
shared topology. Gaussian Cake's core validates and exports the actual library.
Existing sampled clips are retained as migration inputs: their identical slime
frame establishes common splat IDs, and their target endpoints supply the five
forms. The original static models, sources and sampled exports remain available.
No new pairwise clips are baked by the form-library build.

```powershell
godot --headless --path . --editor --import --quit
godot --headless --path . --script res://tests/slime_forms_test.gd
godot --headless --path . --script res://tests/slime_third_person_test.gd
godot --headless --path . --script res://tests/slime_pixel_test.gd
godot --path . res://examples/slime/playground.tscn -- --slime-capture --slime-mode=splats --slime-form=mushroom
```

Captures go to `out/slime/`. The form integration test covers every directed pair,
interruptions, renderer switches, shared topology and eyes, duration, physical
movement during morphing, trigger entry/reentry, and stable gameplay collision.
