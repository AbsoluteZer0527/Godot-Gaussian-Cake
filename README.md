# Gaussian Cake for Godot

A Godot editor addon and runtime player for assets exported by
[Gaussian Cake](https://github.com/AbsoluteZer0527/Gaussian-Cake). The authoring
tool prepares models and correspondence; this addon imports the exports and
plays them in your game. Its **Gaussian Cake** editor dock can also prepare a
splat morph directly from two PLY/GLB files using the separate `gc_cli` executable.
Playback requires no custom Godot build, C++ compiler or native extension.
Tested on **Godot 4.7.2, desktop Compatibility renderer**.

## Try it

Import this repository's `project.godot` and let the editor finish importing. The
plugin is already enabled. Use the Inspector preview below, or open a sample
scene and press **F6** to run it:

| Scene | What to try |
|---|---|
| [Inspector form preview](examples/form_preview.tscn) | Select **Forms**, then use **Morph Preview** in the Inspector without running the game. |
| [Complex transitions](examples/transitions/showcase.tscn) | Cactus, lighthouse island and reef; orbit, scrub, auto-cycle, **B** for shared/refined mapping, **P** for pixel/raw rendering. |
| [Slime playground](examples/slime/playground.tscn) | Walk into items to morph. **WASD/arrows** move, **RMB/Q/E** orbit, **R** returns to slime, **M** switches mesh/splats, **P** switches presentation. |
| [Topology preview](examples/topology_preview.tscn) | A small animated GLB example. |
| [Splat preview](examples/splat_preview.tscn) | A small baked Gaussian clip example. |

**F5** runs the project's configured main scene. The [slime guide](examples/slime/README.md) and
[showcase guide](examples/transitions/README.md) describe their editable node trees,
assets and controls.

## Use it in your game

To start from model files, choose **Project → Tools → Prepare Gaussian Cake
morph…**, or click **Prepare PLY/GLB models…** on a form player's Inspector.
This opens the **Gaussian Cake** dock.
Choose **Source Model** and **Target Model**, then click **Prepare**. The addon
imports the result and assigns it to the selected form player, or adds a
`PreparedMorph` node to the open scene. Select that node and use **Morph Preview**
to scrub or play. This workflow prepares Gaussian splats from PLY captures or
static GLB/PLY meshes; arbitrary mesh topology conversion is separate.

The dock detects `gc_cli` in a sibling `Gaussian-Cake/build/Release/` checkout.
Otherwise select it once under **Preparation settings → Gaussian Cake CLI**.
The executable is needed only during preparation. See
[preparing models in Godot](docs/GETTING_STARTED.md#prepare-plyglb-models-in-godot).

1. Copy `addons/gaussian_cake/` into your project's `addons/` folder.
2. Enable **Gaussian Cake** in **Project → Project Settings → Plugins**.
3. Copy an exported asset or complete form-library folder into the project and
   let Godot import it.
4. Add the appropriate node through **Add Node**, assign its asset, and provide
   an active `Camera3D`.

| Node | Use for | Inspector assignment |
|---|---|---|
| `GaussianCakeFormPlayer3D` | Direct, interruptible transitions between named forms | **Library Path** → exported `library.json` |
| `GaussianCakeTopologyPlayer3D` | One baked mesh animation | **Topology Asset → Source Scene** → animated `.glb` |
| `GaussianCakeSplatPlayer3D` | One baked Gaussian animation | **Splat Asset → Clip** → `.gcsplat` |

For the slime-style workflow, use **GaussianCakeFormPlayer3D**. It loads
`forms.gcforms`, optional topology/color assets, and optional refined pair maps.
Only the addon and exported runtime assets are required in your game.

To preview without writing code, select the form player and expand **Morph
Preview** in the Inspector. Choose **Source** and **Target**, scrub **Progress**,
or use **Play / Pause**, **Reset**, and **Loop**. The node's **Duration** sets
preview speed. Preview settings are saved for editing and do not change the
game's starting pose. See [Inspector preview](docs/GETTING_STARTED.md#preview-in-the-inspector-without-code).

Select a form player and open **Form states** at the bottom to connect forms and
set transition durations. Save the scene to keep its graph override. Geometry is
shared across all arrows; no per-pair GLB export is needed. See the
[form guide](docs/FORM_LIBRARIES.md).

Gameplay can still request named forms directly:

```gdscript
extends Node3D

@onready var forms = $Morph

func _ready() -> void:
	await forms.wait_until_ready()
	if not forms.initialized:
		push_error(forms.error)
		return
	forms.morph_to("apple", 2.5)

func touch_mushroom() -> void:
	if forms.initialized:
		forms.morph_to("mushroom", 2.5)
```

Assign `Morph`'s **Library Path** before running, and use names that exist in that
library. A form player uses normalized `seek(0.5)`; a baked-clip player uses
`seek(seconds)`. See the **[getting-started guide](docs/GETTING_STARTED.md)** for
the node tree, Inspector settings, API, authoring commands and export setup.

## What belongs where

- **Gaussian Cake:** model preparation, shared correspondence, transport
  refinement and portable export.
- **This addon:** the preparation dock that invokes the authoring CLI, import
  validation, playback state, interpolation and Gaussian rendering. A refined
  pair map changes correspondence; it does not add animation
  frames. Interrupted refined transitions use the stable-ID fallback.
- **Your game or sample scene:** movement, collisions, triggers, camera behavior
  and pixel/toon presentation. The addon does not automatically add those systems.

The current splat profile uses prelit DC color and supports up to **50,000 splats
per form/clip**, with a 512 MiB input-file budget. Transparency sorting and
overdraw still cost runtime work. Dynamic splat lighting, view-dependent SH,
streaming and globally sorted overlapping clouds are outside the current scope.
See [performance notes](docs/SPLAT_PERFORMANCE.md),
[form-library authoring](docs/FORM_LIBRARIES.md) and [file formats](docs/FORMAT.md).

## Verify and export

From this repository, replacing `godot` with your executable:

```sh
python tools/verify.py --godot /path/to/godot
python tools/verify.py --godot /path/to/godot --cli /path/to/gc_cli
godot --headless --path . --editor --export-pack "Desktop PCK" out/gaussian-cake.pck
godot --main-pack out/gaussian-cake.pck
```

Verification checks runtime behavior, an isolated addon installation, editor
integration and packaged playback. Passing `--cli` also checks real PLY/GLB
preparation, cache reuse, cancellation, scene assignment and generated-asset
exports. Logs and temporary projects stay under ignored `out/`. The supplied
export preset includes the sample JSON manifests; the addon adds manifests from
`gaussian_cake_generated/` automatically. Other library manifests need an export
include filter. See
[shipping your game](docs/GETTING_STARTED.md#ship-the-game).
