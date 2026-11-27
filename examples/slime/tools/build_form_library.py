"""Prepare the owned five-form correspondence, then export through Gaussian Cake.

python examples/slime/tools/build_form_library.py --cli ../Gaussian-Cake/build/Release/gc_cli.exe
Use --prepare-only to write editable authoring inputs without invoking the CLI.
The old animated clips are migration inputs; no new pairwise clips are baked.
"""
import argparse
import importlib.util
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("owned_slime_geometry", ROOT / "authoring/model_geometry.py")
geo = importlib.util.module_from_spec(spec)
spec.loader.exec_module(geo)
NAMES = ["slime", "mushroom", "stone", "apple", "crate"]


def parts(name):
    pieces = geo.make_model(name, True)
    body = geo.triangles([pieces[0]], name)
    eyes = geo.triangles(pieces[-2:])
    details = geo.triangles(pieces[1:-2])
    return body + eyes, details


def prepare():
    directory = ROOT / "authoring/forms"
    directory.mkdir(parents=True, exist_ok=True)
    geometry = {name: parts(name) for name in NAMES}
    common_count = len(geometry["slime"][0])
    assert all(len(core) == common_count for core, _ in geometry.values())
    detail_owners = [name for name in NAMES if geometry[name][1]]
    forms = []
    for name in NAMES:
        core, _ = geometry[name]
        triangles = list(core)
        body_vertices = [vertex for tri in core for vertex in tri[:3]]
        low_y = min(vertex[1] for vertex in body_vertices)
        high_y = max(vertex[1] for vertex in body_vertices)
        anchor = (0.0, (low_y + high_y) * 0.5, 0.0)
        # Every accessory has a permanent vertex slot. An absent accessory is
        # tiny and inside the opaque body, preserving topology and exact eyes.
        for owner in detail_owners:
            for triangle in geometry[owner][1]:
                if owner == name:
                    triangles.append(triangle)
                else:
                    center = geo.mul(geo.add(geo.add(triangle[0], triangle[1]), triangle[2]), 1 / 3)
                    vertices = [geo.add(anchor, geo.mul(geo.sub(v, center), 0.0001)) for v in triangle[:3]]
                    triangles.append((*vertices, triangle[3], core[0][4], triangle[5], 1.0))
        forms.append({
            "name": name,
            "positions": [v for triangle in triangles for v in triangle[:3]],
            "normals": [triangle[3] for triangle in triangles for _ in range(3)],
            "colors": [geo.linear(triangle[4]) for triangle in triangles for _ in range(3)],
        })
    count = len(forms[0]["positions"])
    assert all(len(form["positions"]) == count for form in forms)
    topology = {
        "format": "GaussianCakeSharedTopology", "version": 1, "names": NAMES,
        "indices": list(range(count)), "forms": forms,
    }
    (directory / "shared_topology.json").write_text(json.dumps(topology, separators=(",", ":")) + "\n", encoding="utf-8")
    manifest = json.loads((ROOT / "assets/manifest.json").read_text(encoding="utf-8"))
    endpoints = []
    for name in NAMES:
        clip_name = "mushroom" if name == "slime" else name
        endpoints.append({
            "name": name,
            "clip": f"../../assets/morphs/slime_to_{clip_name}.gcsplat",
            "frame": 0 if name == "slime" else 12,
            "scale": manifest["forms"][name]["scale"],
            "center": manifest["forms"][name]["center"],
        })
    project = {
        "format": "GaussianCakeFormProject", "version": 1, "default_duration": 1.5,
        "topology": {"path": "shared_topology.json"},
        "splats": {"reference": "slime", "forms": endpoints},
    }
    path = directory / "slime.gcformproject"
    path.write_text(json.dumps(project, indent=2) + "\n", encoding="utf-8")
    print(f"Prepared {len(NAMES)} forms with {count} shared vertices and 48,000 shared splat IDs")
    return path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cli", type=Path)
    parser.add_argument("--prepare-only", action="store_true")
    args = parser.parse_args()
    if not args.prepare_only and not args.cli:
        parser.error("--cli is required unless --prepare-only is selected")
    project = prepare()
    if not args.prepare_only:
        subprocess.run([str(args.cli.resolve()), "forms", str(project), "--output", str(ROOT / "assets/forms")], check=True)


if __name__ == "__main__":
    main()
