# Gaussian Cake for Godot

A Godot 4 addon for playing shared-topology GLB animations and animated Gaussian
splat clips exported by [Gaussian Cake](https://github.com/AbsoluteZer0527/Gaussian-Cake).
Version 0.1.0 targets desktop **Godot 4.7.2, Compatibility renderer**.

The authoring application does the baking. This repository owns the importer,
player nodes, shader, and small integration examples. It needs no C++ compiler,
native extension, authoring-tool checkout, or external package to run.

## Try the included examples

1. Import this repository's `project.godot` into Godot and let assets import.
   The Gaussian Cake plugin is already enabled in this project.
2. Press **F5** for the topology example.
3. Open `examples/splat_preview.tscn` and press **F6** for splats.

**Space** plays/pauses, **Left/Right** orbit, and the slider scrubs.
Both scenes contain editable camera, stage, lighting, and UI nodes.
Their procedural round-to-tall fixtures are included: 114 mesh vertices and
4,096 splats respectively. This is a playback example, not the slime game.

## Install in another game

1. Copy **`addons/gaussian_cake/`** into your project's `addons/` directory.
2. Enable **Gaussian Cake** in **Project → Project Settings → Plugins**.
3. Copy your exported `.glb` or `.gcsplat` into the game and let it import.
4. Add one of these nodes through **Add Node**:

| Node | Inspector assignment |
|---|---|
| `GaussianCakeTopologyPlayer3D` | Drag the imported GLB into **Topology Asset → Source Scene**. |
| `GaussianCakeSplatPlayer3D` | Drag the imported `.gcsplat` into **Splat Asset → Clip**. |

Only the addon folder is required. Keep a `Camera3D` in the game scene.
The included examples, tests, tools, and source `.gcproject` files are optional.

## Playback and editor preview

Both nodes expose **Autoplay**, **Speed**, and **Loop Mode** (Once, Loop,
Ping Pong). **Editor Preview → Preview Progress** chooses a static pose from
0 to 1 in the editor; it does not change the runtime starting time. The splat
editor preview follows the first 3D editor viewport. Keep the addon enabled for
editor preview and importing. Runtime players do not call editor APIs.

```gdscript
@onready var morph = $GaussianCakeSplatPlayer3D

func _ready() -> void:
	morph.playback_finished.connect(_on_morph_finished)
	morph.play()

func _on_morph_finished() -> void:
	print("Finished") # Emitted once at the end in Once mode.

func show_halfway() -> void:
	morph.pause()
	morph.seek(morph.duration * 0.5)
```

| API | Behavior |
|---|---|
| `play()` | Resume; restart from zero if Once playback already finished. |
| `pause()` | Hold the current pose. |
| `stop()` | Pause and return to zero. |
| `seek(seconds)` | Clamp to the clip, apply immediately, preserve playing/paused state. Starts the forward leg in Ping Pong. |
| `duration`, `time`, `progress` | Read-only duration/time in seconds and normalized progress. |
| `playing`, `error` | Current playback state and last asset/setup error. |
| `playback_finished` | Signal at completion in Once mode, after the endpoint is applied. |
| `playback_error(message)` | Signal on asset/setup failure; the same message appears as an editor node warning. |

Topology: leave **Animation Name** empty to use the first non-RESET animation,
or enter the full imported animation name. The GLB must have **Animation →
Import** enabled. `get_animation_names()` returns available names. The player
does not modify the shared Animation's loop mode. **Use Vertex Colors** enables
COLOR_0 on a per-instance material override when Godot leaves it disabled;
textures and the other material properties are preserved. Turn it off to keep
the imported material's original vertex-color setting.

Splats: the **Camera** override is optional. By default, the player uses its
viewport's active camera. It continues sorting when paused if the camera or
player transform changes. Separate players share clip data but have independent
clocks, materials, textures, and instance buffers.

## Importing and shipping splats

The importer recognizes **GCSPLAT version 1**. It validates dimensions, byte
length, timestamps, bounds, finite attributes, quaternion normalization, scale,
color, and opacity. Invalid data produces an import error with a reason.

Godot stores a `GaussianCakeSplatClip` binary Resource in its import cache. Scenes
reference the original `.gcsplat` path through Godot's resource remapping. A
normal game export includes the imported resource automatically: **no manual
`*.gcsplat` non-resource filter is required**. Keep `.import` sidecars in Git and
ignore `.godot/`; a fresh checkout rebuilds the cache.

Replacing a source clip triggers reimport. Open players rebuild when their
resources change. Enable the addon and let the editor finish its filesystem scan
before importing. If a file was copied while the addon was disabled, enable it
and use Reimport after scanning completes.

## Current scope and limits

- Desktop Compatibility is the tested renderer. Other renderers/platforms are unverified.
- One baked transition per asset. Baking, `.gcproject` editing, and topology generation stay in Gaussian Cake.
- Splat files are capped at 512 MiB; importer and player cap at 50,000 splats.
  Start with about 5,000. The importer offers a smaller **Limits → Max Splats** cap.
- CPU depth sorting and GDScript updates are intended for modest clouds. The
  file budget is not a total RAM budget; validation temporarily copies attributes.
- A single camera/cloud is the visual correctness target. Spatially separated
  instances work independently; overlapping clouds and other transparent objects
  are not globally sorted. Split editor viewports share the first camera's order.
- Splats use prelit DC color and alpha blending. No view-dependent SH, dynamic
  lighting/shadows, collision mesh, streaming, GPU sort, or automatic toon/pixel pass.
- The near plane clips by splat center; opaque depth intersections are approximate.
- Imported topology keeps the exported fitted mesh and its starting appearance.
  Shape/material changes that were not exported cannot be recovered by the addon.

## Tests and exports

Replace `godot` with your Godot executable:

```sh
godot --headless --path . --editor --import --quit
godot --headless --path . --script res://tests/run_tests.gd
python tools/verify.py --godot /path/to/godot
```

The Python verification command runs runtime tests, copies only the addon and
two exported assets into an isolated project, checks editor preview and plugin
enable/disable, changes a clip to verify live reimport, and exports/runs a PCK.
It fails on engine errors as well as test failures. Logs and isolated test
projects stay under ignored `out/` for inspection.

For the included project, export a PCK without installing export templates:

```sh
godot --headless --path . --editor --export-pack "Desktop PCK" out/gaussian-cake.pck
godot --main-pack out/gaussian-cake.pck
```

An executable export needs Godot's matching export templates. The preset excludes
editor-only code and tests; runtime playback uses only imported resources.

Fixtures can be regenerated using the authoring repository's CLI:

```sh
python tools/generate_assets.py --cli ../Gaussian-Cake/build/Release/gc_cli.exe
```

The `.obj`, `.gcproject`, `.glb`, and `.gcsplat` fixtures are intentionally small,
tracked assets. The generator, included projects, and [format reference](docs/FORMAT.md)
record how they were produced. The slime game should consume a tagged addon
release from its own repository.
