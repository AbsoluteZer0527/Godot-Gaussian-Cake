# Splat playback performance

The original player decoded positions, invoked a GDScript sorting callback for
every comparison, and uploaded the full MultiMesh buffer whenever the camera or
player moved. At 48,000 splats the CPU work dominated frame time. Lowering the
viewport resolution alone cannot solve that CPU cost.

The optimized player caches the two active frames' positions, sorts packed integer
depth keys using Godot's native sort, and uploads a small slot-to-splat texture.
Instance transforms and IDs remain fixed. Sorting skips pure translations because
they add the same depth offset to every splat. Camera/model rotation and morphing
still update the order. Float32 depth keys retain signed ordering and deterministic
ID ties, including signed zero. No splats are removed.

## Measurement

Measured on the development Windows machine in Godot 4.7.2, using the same 48,000
splat asset, headless CPU update benchmark, 60 samples per case:

| Operation | Original mean | Optimized mean |
|---|---:|---:|
| Camera rotation | 111.2 ms | 8.0 ms |
| Morph update | 107.6 ms | 9.35 ms |
| Pure translation | 87.4 ms | 0.001 ms |
| Unchanged view and pose | 0.001 ms | 0.001 ms |

These timings measure CPU update work and API submission, **not whole-game FPS or
GPU rendering time**. Transparent overdraw, screen coverage, loading, and other
game systems still affect frame rate. The small order texture is about 192 KB at
48,000 splats, compared with the old roughly 3 MB instance buffer upload.

A separate real-renderer sample run on the RTX 5070 Laptop GPU, at 1100x720 with
the pixel pass enabled and VSync disabled, observed about 100 FPS while orbiting
and repeatedly morphing the 48,000-splat player (9.94 ms mean frame interval,
15.39 ms p95). This is a warmed, short diagnostic run, not a cross-device FPS
guarantee. `tests/slime_frame_benchmark.gd` reproduces that workload.

```sh
godot --headless --path . --script res://tests/perf_splats.gd
godot --headless --path . --script res://tests/splat_sort_test.gd
```

The sample also prepares resource loading and lazy clip validation away from the
main thread. This addresses the separate first-use hitch; validation is still
performed before the clip is assigned to a renderer. Only the selected render
mode is active. The addon remains a Compatibility renderer implementation with
CPU sorting, not a GPU sorting or streaming implementation.

## Pixel appearance

The original sample only rendered into a low-resolution viewport. SyntaxSplat's
pixel appearance additionally uses ordered dithering and nearest-palette color
selection. The revised sample applies those operations to the world viewport,
then enlarges it with nearest filtering. The HUD remains at native resolution.
This is a sample-level presentation pass shared by mesh and splat modes; it does
not replace Gaussian geometry with a triangle mesh.
