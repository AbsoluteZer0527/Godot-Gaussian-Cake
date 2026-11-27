# Using the Gaussian Cake addon

Gaussian Cake prepares morphable assets outside Godot. The addon loads those
exports and plays them as normal `Node3D` children. It is a Godot editor plugin
with runtime scripts, not a modification to the Godot engine.

The tested setup is **Godot 4.7.2, desktop Compatibility renderer**. Playback
requires only Godot, the addon folder and exported assets. Preparing new assets
uses the separate Gaussian Cake `gc_cli` executable, which can run from the
addon's editor dock.

## Run the existing examples

Import this repository's `project.godot` and wait for importing to finish. Open
one of these scenes; use the Inspector for the first example, or **F6** to run a
scene:

| Scene | Purpose |
|---|---|
| `examples/form_preview.tscn` | Select **Forms** and use **Morph Preview** directly in the Inspector; no game script needed. |
| `examples/slime/playground.tscn` | A controllable slime that morphs into touched items; topology and splat modes. |
| `examples/transitions/showcase.tscn` | Cactus/island/reef transitions with shared/refined correspondence and pixel/raw comparison. |
| `examples/topology_preview.tscn` | Baked mesh animation playback. |
| `examples/splat_preview.tscn` | Baked Gaussian animation playback. |

**F5** runs whichever scene is configured as the project main scene. Example controls and asset
details are in the [slime](../examples/slime/README.md) and
[transition](../examples/transitions/README.md) guides.

## Install in another project

1. Create or open a Godot project, using Compatibility for the tested rendering
   path.
2. Copy this repository's `addons/gaussian_cake/` folder to
   `your_game/addons/gaussian_cake/`.
3. Enable **Gaussian Cake** in **Project → Project Settings → Plugins**.
4. Copy the exported assets into your project and wait for Godot's import scan.
   If assets arrived before the plugin was enabled, reimport them after enabling it.

The examples, `tools/`, tests, source PLYs and authoring projects are optional.
Godot's [plugin installation guide](https://docs.godotengine.org/en/stable/tutorials/plugins/editor/installing_plugins.html)
describes this standard addon installation flow.

## Prepare PLY/GLB models in Godot

1. Open a 3D scene, then choose **Project → Tools → Prepare Gaussian Cake morph…**.
   You can also click **Prepare PLY/GLB models…** in a form player's Inspector
   to open the **Gaussian Cake** dock. Select
   an existing `GaussianCakeFormPlayer3D` if you want to replace its library;
   otherwise preparation adds a `PreparedMorph` node to the scene.
2. Browse for **Source Model** and **Target Model**, or drag files from Godot's
   FileSystem dock into those fields. Files outside the project also work.
   Supported inputs are Gaussian PLY captures, PLY meshes with faces, and static
   GLB meshes. Both lowercase and uppercase file extensions are accepted.
3. Choose **Splats per form**; the default is 12,000 and the maximum is 50,000.
4. If the preparation tool was not detected, expand **Preparation settings** and
   browse to `gc_cli.exe` (or `gc_cli` on other desktop systems). For this machine,
   it is in the separate `Gaussian-Cake/build/Release/` directory. The addon
   checks that sibling checkout and the optional `GAUSSIAN_CAKE_CLI` environment
   variable. The selected path is remembered locally for this project.
5. Click **Prepare**. Preparation runs outside the editor process; stage status,
   an activity indicator and **Preparation log** show its state. **Cancel** stops
   the job. Successful results are validated, imported and assigned automatically.
6. The selected form player's **Morph Preview** section opens. Scrub **Progress**
   or use **Play / Pause**, **Reset**, **Loop** and **Duration**. Source and target
   names come from the model filenames. Assignment and node creation support
   normal scene undo/redo. Press **F** with the 3D viewport focused to frame the
   selected model if it is outside your editor camera view.

For a first trial, choose `examples/slime/assets/models/slime.glb` and
`examples/slime/assets/models/apple.glb` from this repository.

If the edited scene changes during preparation, the result stays available in the
dock: open the intended scene and click **Use in scene**. The same button lets you
reuse a prepared result on another node. Save your scene after assigning it.

This panel prepares a **splat form library**, including when the input is a GLB
mesh. It establishes corresponding Gaussian identities once and stores two
endpoints. Animation frames are interpolated at runtime, so changing duration or
preview progress needs no further cooking. It does not automatically construct
shared-topology mesh forms from arbitrary files. Existing prepared topology
libraries still work through Library Path and Renderer Mode.

**Preparation settings** also contains matching samples, matching groups and
color matching strength. For Gaussian captures with view-dependent spherical
harmonic color, the current player needs base color. Enable **Use base color
only** to explicitly permit discarding the extra color data, then prepare again.
Static GLB geometry uses its supported vertex/base color and textures; skinning
and animation are not evaluated during this preparation.

Successful assets live under `res://gaussian_cake_generated/<cache-key>/`. Keep
that complete directory and its import sidecars with your game. The source files
and CLI are needed only when preparing again. Source contents, external GLB image
or buffer dependencies, settings and the CLI binary determine cache reuse.
Unchanged inputs reuse validated results; failures and cancellation preserve the
previous scene assignment. Temporary projects remain under
`.godot/gaussian_cake/preparation/` and are not game assets.

The enabled addon includes generated `library.json` manifests automatically in
game exports. Use **Export all resources** to include their imported `.gcforms`
payloads. If selecting resources manually, include those payloads explicitly.
Libraries copied elsewhere still need their JSON paths in the export include
filter described under **Ship the game** below.

## Choose a player

| Node | Input | Control model |
|---|---|---|
| `GaussianCakeFormPlayer3D` | A form library's `library.json` | Choose named destinations at runtime, including during a morph. |
| `GaussianCakeTopologyPlayer3D` | An animated shared-topology `.glb` | Play, pause or seek one baked mesh animation. |
| `GaussianCakeSplatPlayer3D` | A `.gcsplat` clip | Play, pause or seek one baked Gaussian animation. |

Use the **form player** for slime → apple → mushroom without returning to slime
or baking every animation pair. Use the two clip players for an existing baked
timeline animation. Their `seek()` units differ, as explained below.

## Set up a form player

For a first test, copy `examples/slime/assets/forms/` into
`your_game/assets/slime/`. Keep these files together:

| File | Role |
|---|---|
| `library.json` | Names and paths for the exported bundle. |
| `forms.gcforms` | Gaussian endpoint records; required by the current form player. |
| `forms.glb` and `form_colors.png` | Shared-topology shapes and their color atlas, when exported. Both are needed for topology mode. |
| Referenced `.gcmap` files | Optional refined pair correspondences. Copy every map listed in the manifest. |

The complex-transition bundle is splat-only, so it has no topology GLB or color
atlas. It automatically uses splat rendering. The core authoring tool can also
export topology-only libraries, but this version of the form player still
requires a splat library, even when displaying topology.

Create an editable scene tree like this:

```text
Playground (Node3D)
├── Camera3D                         # Set Current, aim at the player
├── Player (CharacterBody3D)
│   ├── CollisionShape3D             # Your gameplay collider
│   └── Morph (GaussianCakeFormPlayer3D)
└── ...                             # Ground, item triggers, UI
```

Select **Morph** and assign:

| Inspector field | Setting |
|---|---|
| **Library Path** | `res://assets/slime/library.json` |
| **Camera** | Your `Camera3D`, or leave empty to use the viewport's active camera. |
| **Renderer Mode** | `topology` or `splats`; topology requires the exported mesh and atlas. |
| **Duration** | Default transition time in seconds, for example `2.5`. |
| **Transport Mode** | `shared` for common IDs; `refined` to use available exported pair maps. |
| **Paused** | Leave off for normal playback. |

The form player creates its rendering children from the library. It does not
create a camera, movement controller, collision shape, pickup trigger or gameplay
logic. Keep those in the surrounding scene. The visible morph does not deform
the gameplay collider automatically.

### Preview in the Inspector without code

For a ready-to-use example, open `examples/form_preview.tscn` and select **Forms**.
Stay in the editor; pressing Play/F6 is not required for Inspector preview.

1. Select the `GaussianCakeFormPlayer3D` node and assign **Library Path**.
2. Expand **Morph Preview**. Choose **Source** and **Target** from the library's
   form-name dropdowns.
3. Drag **Progress** from `0` (source) to `1` (target), or click **Play / Pause**.
   **Reset** stops playback and returns to the source. Enable **Loop** to repeat.
4. Set **Duration** for the preview speed. Change **Renderer Mode** to compare
   topology and splats; choose **Transport Mode → refined** to use an available
   pair map. The status line reports preparation, errors or fallback behavior.

The editor prepares correspondence order when the pair changes, then reuses it
while scrubbing. During preparation, the most recent selection and progress are
applied when ready. Changing the library refreshes the dropdowns and replaces
names that no longer exist with valid defaults. A splat-only library automatically
uses splat rendering.

Source, target, progress and loop are saved as **editor preview settings**. Form
selections and manual progress edits use Godot's normal Inspector undo/redo.
Preview playback stops when the node is deselected or the addon is disabled.
Starting the game still uses the library's reference form and existing gameplay
code; editor preview does not add runtime autoplay or alter the runtime Paused
setting. Generated rendering children are not saved into the scene.

The 3D editor viewport previews the model using its editor camera. The sample's
pixel/palette pass is part of its game viewport; run that scene with **F6** to
judge the final pixel presentation.

### Drive forms from gameplay

Attach this example to the `Player` node. Assign Library Path in the editor before
running, since `wait_until_ready()` waits for that configured library to load:

```gdscript
extends CharacterBody3D

@onready var forms = $Morph

func _ready() -> void:
	await forms.wait_until_ready()
	if not forms.initialized:
		push_error("Cannot load morph library: " + forms.error)
		return
	forms.morph_finished.connect(_on_morph_finished)

func morph_into(form_name: String) -> void:
	if forms.initialized and forms.error.is_empty():
		forms.morph_to(form_name, 2.5)

func _on_morph_finished(form_name: String) -> void:
	print("Now showing: ", form_name)
```

Call `morph_into("apple")` from an item's `Area3D.body_entered` handler, after
checking that the entering body is your player. Calling `morph_into("mushroom")`
while the apple transition is running redirects it from the displayed pose.
The supplied slime library names are `slime`, `apple`, `mushroom`, `stone` and
`crate`; other libraries have their own names in `library.json` and `forms.names`.

### Form playback controls

```gdscript
forms.morph_to("apple", 2.5)    # Explicit duration in seconds
forms.morph_to("mushroom")     # Uses the node's Duration
forms.set_renderer("splats")   # Preserves the current transition progress
forms.paused = true
forms.seek(0.5)                # Normalized progress: 0=start, 1=end
forms.resume()                 # Resumes, including after a manual seek
forms.snap_to_form("slime")    # Immediate canonical endpoint, no transition
```

`seek()` changes the pose but does not pause an active clock by itself. Set
`paused = true` before scrubbing. Calls to `seek()` or `snap_to_form()` while
endpoint preparation is in progress are ignored; wait until `loading` is false
before driving these controls from an automated script. `morph_to()` can accept
a new destination during preparation and keeps the latest request.

Useful state includes `initialized`, `loading`, `morphing`, `progress`, `error`,
`current_form`, `target_form`, `names` and `splat_count`. `current_form` is the
last completed named endpoint, not a name for an in-between pose. The
`library_ready`, `state_changed` and `morph_finished(form)` signals support UI and
gameplay integration. `wait_until_settled()` waits for loading and playback to
finish; a paused in-progress morph will remain unsettled until resumed.

### Shared and refined correspondence

`shared` uses the correspondence prepared against one reference form, so every
named pair can play without a dedicated pair map. `refined` uses a `.gcmap` when
the transition starts at a named endpoint with a matching exported map.

Refined mappings are composed through the current endpoint IDs. A sequence such
as cactus → island → reef → cactus therefore preserves every endpoint's splat
set without resetting through the reference model. An interrupted pose has no
exact exported pair map, so the player snapshots that pose and uses the
stable-ID fallback. Missing maps also fall back. `last_transport` reports
`shared`, `refined` or `fallback`; `transition_metrics` exposes the map's authored
cost measurements. Godot does not run a new transport solver every frame.

## Prepare your own assets

In the Gaussian Cake desktop tool, open **Project & Export → Real-time form
library…**, open a `.gcformproject`, preview its destinations, and use **Export
form library**. For splat-only projects, **Refine splat transport** prepares the
next preview transition on a worker. Export can include the selected canonical
Start form ↔ destination map.

The equivalent commands run from the **Gaussian-Cake authoring repository**:

```powershell
./build/Release/gc_cli.exe forms path/to/project.gcformproject --output out/my-forms
./build/Release/gc_cli.exe refine-forms out/my-forms/library.json --pairs cactus:island,island:reef,reef:cactus --color-weight 0.35 --passes 8 --neighbors 24
```

Replace the pair names with names in your project. Refinement is optional and
writes selected forward/inverse maps without changing the endpoint payload.
Changing the duration does not require rebuilding intermediate animation frames.
Rebuilding the endpoint library requires rebuilding its pair maps too.

Source preparation and the `.gcformproject` contract are documented in
[form-library authoring](FORM_LIBRARIES.md). The example
`examples/transitions/authoring/complex.gcformproject` references portable source
PLYs beside it. An arbitrary PLY is not directly a playable form library: the
authoring tool must establish the common endpoint count and correspondence first.

## Play a baked GLB or splat clip

For a GLB animation, add `GaussianCakeTopologyPlayer3D` and drag the imported GLB
into **Topology Asset → Source Scene**. Leave **Animation Name** empty for the
first non-RESET animation, or enter a full name returned by
`get_animation_names()`. Keep **Animation → Import** enabled in the GLB import
settings. **Use Vertex Colors** applies a per-instance material override when
Godot leaves the imported vertex colors disabled.

For a baked splat animation, add `GaussianCakeSplatPlayer3D` and drag the imported
`.gcsplat` into **Splat Asset → Clip**. Its optional **Camera** override otherwise
falls back to the viewport's active camera.

Both clip players expose **Playback → Autoplay, Speed, Loop Mode** and
**Editor Preview → Preview Progress**. The preview slider chooses a static editor
pose without changing the runtime start time. Their shared runtime API is:

```gdscript
clip_player.play()
clip_player.pause()
clip_player.seek(clip_player.duration * 0.5) # Seconds, unlike form-player seek()
clip_player.stop()                         # Pause and return to zero
```

Loop Mode supports Once, Loop and Ping Pong. `play()` restarts a completed Once
clip; `seek(seconds)` preserves its playing/paused state. `playback_finished`
signals completion in Once mode, and `playback_error(message)` reports setup
errors. `duration`, `time` and `progress` expose seconds and normalized progress.

## Add the pixel presentation

The addon renders Gaussian geometry and source color. Pixel/toon presentation is
implemented by the sample scene, separately from the player. The samples render
the world into a smaller `SubViewport`, enlarge it with nearest filtering, and
apply a palette/dither material on the `SubViewportContainer`. Their HUD stays
at native resolution.

Reuse that scene structure and its palette/shader when bringing the style into
your game. If using the showcase's external palette JSON, retain its path and
include it in the game export too. See the
[slime pixel setup](../examples/slime/README.md#pixel-presentation) and
[complex showcase](../examples/transitions/README.md). Increasing the splat count
alone does not add a pixel-art effect. The authored splat colors are prelit;
dynamic lighting and deforming collision are not supplied by this presentation.

## Ship the game

1. Keep `library.json`, `.gcforms`, referenced `.gcmap` files, and any topology
   GLB/color atlas together under the same project-relative folder structure.
2. In the export preset's **Resources** options, use **Export all resources** for
   a first integration. These files are loaded through the manifest; if choosing
   a narrower resource selection, explicitly include the runtime assets too.
3. Add your JSON manifest paths to the **non-resource include filter**, for example
   `assets/slime/library.json`. Include any sample palette JSON you use. The
   included project's preset already lists its sample manifests and palette.
4. Export and test a standalone build. Keep source PLYs/authoring projects out of
   the game with `.gdignore` or the export exclusion filter, as the samples do.

The `.gcforms`, `.gcmap` and `.gcsplat` importers create Godot resources, which
are exported through normal resource remapping. They do not need a raw-file
non-resource include filter. Keep generated `.import` sidecars in version control
and ignore `.godot/`; a fresh checkout rebuilds its cache.

Godot's [export guide](https://docs.godotengine.org/en/stable/tutorials/export/exporting_projects.html)
explains resource selection, non-resource filters and platform export templates.
The supplied Desktop PCK preset can be exercised with:

```sh
godot --headless --path . --editor --export-pack "Desktop PCK" out/game.pck
godot --main-pack /absolute/path/to/game.pck
```

Run the second command from an empty directory when checking that the pack has
all its dependencies. An executable export additionally needs matching Godot
export templates. The addon and imported runtime resources work without enabling
editor plugins inside the exported game.

## Troubleshooting and limits

| Symptom | Check |
|---|---|
| Custom player nodes are missing | The addon is under `addons/gaussian_cake/` and enabled in Plugins. |
| Import errors or missing resource | Let the scan finish, reimport with the addon enabled, and read the editor error message. Keep the complete exported bundle together. |
| Nothing visible | Use an active camera aimed at the model, the correct Library Path/Clip/Source Scene, and check the player's `error` or node warning. |
| Form calls appear to do nothing | Wait for initialization, use a name from `forms.names`, and check `loading` before seeking or snapping. |
| Scrubbing resumes immediately | Set `forms.paused = true` before `forms.seek(progress)`. |
| Pixel style is missing | Copy/adapt the sample viewport and presentation material, not just the player node. |
| Editor works but exported game cannot load | Include the manifest/palette JSON and the imported resource assets in the export preset. |
| Splat playback is slow | Reduce the exported common count, visible clouds and viewport resolution; use the sample FPS/frame benchmarks. |

The tested splat limit is 50,000 per form/clip and 512 MiB per input file. Splats
use prelit DC color, not view-dependent SH. They do not supply dynamic shadows,
lighting, streaming or collision meshes. Sorting is per cloud; overlapping clouds
and other transparent objects are not globally sorted. Other renderers and
platforms need their own validation. See [performance notes](SPLAT_PERFORMANCE.md).
