# Real-time form libraries

The build and CLI commands below run from the **Gaussian-Cake authoring-tool
checkout**. This copy documents the shared export contract used by the Godot addon.

For installing and using the player in a game, start with
[Using the Gaussian Cake addon](GETTING_STARTED.md). The current Godot form
player requires `forms.gcforms`; topology is optional. The core's topology-only
export described below is not a standalone input to this player.

A form library stores a shared set of named endpoint shapes. Prepare each shape
against one reference, then interpolate between any two forms at runtime. Changing
the destination during a morph snapshots the displayed pose and starts from there.
The reference defines identities; the animation never has to visit its shape.

The first profile uses smoothstep timing, linear position/color/opacity blending,
shortest-path quaternion SLERP, and interpolation of log Gaussian scales. It
guarantees pose continuity when redirected, not continuous velocity. Pair-specific
rigid deformation, heat-wave timing, cohesion and spring simulation remain available
through the existing sampled GLB/GCSPLAT export workflow.

## Prepare and export

```powershell
./build/Release/gc_cli.exe forms path/to/slime.gcformproject --output out/slime-forms
```

The exported directory contains `library.json`, `forms.gcforms`, and, when a mesh
library is supplied, `forms.glb` and `form_colors.png`. Topology-only projects omit
the splat file. No animation FPS is needed: duration is a runtime setting and defaults
to 1.5 seconds. Keep all files together when moving the directory.

In the desktop tool, open **Project & Export → Form state machine...** and choose
the `.gcformproject`. Drag forms to arrange the graph. Choose **From** and **To**,
then **Add arrow** and set its duration. Double-click a form to preview it.

**Any form can follow any form** allows direct transitions, with arrows overriding
the default duration. Turn it off to allow only the arrows you create. Set the
**Initial form**, then **Save project** and **Export form library**.

The graph is saved in the project and exported in `library.json`. All arrows
reuse the same `forms.glb` / `forms.gcforms`; adding an arrow needs no new mesh
or sampled animation. Existing projects without a graph allow all transitions.

In Godot, select a **GaussianCakeFormPlayer3D** and open the bottom **Form states**
panel. Connect ports, choose an arrow to change its duration, and save the scene.
These edits override the imported graph for that node and support undo/redo.
**Use library graph** removes the override. Preview plays a canonical source-to-target
pair; game requests can redirect the currently displayed pose.

```gdscript
$Forms.request_state("apple") # Uses the graph's duration; false if no arrow allows it.
```

Arrows are directed. During interruption, the last requested destination is the
logical state used to select the next arrow; the visible morph starts at its
current pose. Requests with no allowed arrow leave playback unchanged. There is
no automatic pathfinding or condition evaluation: gameplay requests a destination.
`morph_to(name, seconds)` also obeys allowed arrows; an explicit duration overrides
the arrow's duration. Existing timeline projects and baked clips remain supported.

Scripted preview/capture uses the same tool renderer:

```powershell
./build/Release/menv.exe --form-project path/to/slime.gcformproject --mode splats `
  --form-target apple --shot out/forms-apple --times 0,0.5,1 --nogui 1
```

Run the desktop executable with its working directory containing `shaders/`.

## Source project

The JSON `.gcformproject` format is separate from timeline `.gcproject` files:

```json
{
  "format": "GaussianCakeFormProject",
  "version": 1,
  "default_duration": 1.5,
  "topology": {"path": "shared_topology.json"},
  "splats": {
    "reference": "slime",
    "forms": [
      {"name": "slime", "clip": "slime_to_apple.gcsplat", "frame": 0,
       "scale": 1, "center": [0, 0, 0]},
      {"name": "apple", "clip": "slime_to_apple.gcsplat", "frame": 12,
       "scale": 1, "center": [0, 0, 0]}
    ]
  }
}
```

Paths resolve relative to the project. Clip migration verifies that every source
frame has identical records in identical ID order. Equal counts alone are not
enough. A target's selected frame is already arranged in reference-ID order.
`scale` multiplies positions and Gaussian radii; `center` is then added to positions.
Use these transforms to restore all forms to one object-local coordinate system.

Alternatively, replace each `clip`/`frame` entry with `source: "shape.ply"` (or a
supported mesh path). The core prepares reference-to-form correspondence once per
form. The splats section accepts `count`, `samples`, `mixtures`, `color_match`,
`size`, `up`, `crop` and `dc_only`. Explicit `dc_only: true` is required to discard
view-dependent SH from captures. Source mode and clip migration cannot be mixed.
Every source must supply the common requested identity set; a mismatched cleaned
count is rejected. Prepared correspondence does not guarantee ideal semantic
matching for arbitrary models: inspect eyes, thin features and intermediate shapes.

Prepared topology JSON contains `format: "GaussianCakeSharedTopology"`, `version: 1`,
`names`, one shared `indices` array and ordered `forms`. Each form contains `name`,
`positions`, `normals`, and linear RGB `colors` as arrays of triples. Every form
uses the same vertex order. The current slime builder uses a common body and eyes
plus fixed accessory slots; absent accessories collapse inside the body. This is
not an automatic remesher for arbitrary models with incompatible topology.

## Runtime and ownership

`gc_core` owns validation and the CPU reference evaluator (`FormLibrary.h`). Its
players support binding a library, changing destination, seeking and advancing
time. `gc_io` owns project loading, migration/preparation and portable exports.
The desktop adapter owns ImGui/OpenGL; it uploads endpoints on a transition and
uses the existing GPU interpolation/radix-sort renderer when compute is available.

This repository's form player imports the library and provides
`morph_to(name, seconds)`. The slime sample's 1.5-second duration is editable on
the Player node; the complex showcase has a four-second duration control.
Both renderers keep the same clock;
movement, camera orbit and the stable gameplay collider remain independent.

The Godot renderer still sorts visible Gaussian centers. Endpoint storage removes
sampled animation frames and per-pair clips; it does not eliminate transparency
sorting or overdraw. Existing renderer optimizations remain in their respective
OpenGL and Godot backends.

## GCFORMS v1 binary contract

The optional `state_machine` object in `.gcformproject` and `library.json` has
`version: 1`, an `initial` form name, `allow_any`, a `positions` array in form-name
order (empty or one `[x,y]` per form), and directed `transitions` with `from`, `to`,
and `duration` in seconds. Unknown names, duplicate arrows, invalid positions,
and durations outside 0.01–3600 seconds are rejected. The binary geometry format
is unchanged. This graph profile uses the existing smoothstep interpolation;
custom wave, spring, and rigid motion still use baked clips.


Little-endian integers and IEEE float32; no native struct padding or compression.

| Offset | Field |
|---:|---|
| 0 | 8 bytes: `GCFORMS` followed by zero |
| 8 | u32 version = 1 |
| 12 | u32 header bytes = 64 |
| 16 | u32 identities per form |
| 20 | u32 form count |
| 24 | u32 metadata byte count, padded to a multiple of four |
| 28 | u32 flags = 1 (linear RGB) |
| 32 | u32 record stride = 56 |
| 36 | f32 default duration |
| 40 | 3 f32 conservative AABB minimum |
| 52 | 3 f32 conservative AABB maximum |
| 64 | UTF-8 JSON metadata, padded with spaces |

Metadata is `{"names":[...],"reference":0,"profile":"endpoint-v1"}`. Form-major
records follow: position XYZ (3 floats), unit quaternion XYZW (4), log positive
scale XYZ (3), linear RGB (3), straight opacity (1). The file length is exactly
`64 + metadata_bytes + forms * identities * 56`. Unknown versions, malformed
metadata, invalid attributes, inconsistent identities and truncated files fail
before playback. Libraries are limited to 512 MiB; the Godot renderer supports
at most 50,000 splats per form.

The mesh GLB has the reference as its base and named relative blend shapes for
the remaining forms. Appearance is a separate linear-RGB atlas, 1024 pixels wide,
with `ceil(vertices/1024)` rows per form. The addon blends its rows with the same
weights as the mesh. Standard GLB blend shapes alone do not animate vertex colors.

## Verification

```powershell
cmake --build build --config Release --target gc_form_library_tests
ctest --test-dir build -C Release -R gc_form_library_tests --output-on-failure
```

The companion addon tests cover malformed files, direct transitions, interruption
continuity, runtime duration, renderer changes, physics triggers and package export.
