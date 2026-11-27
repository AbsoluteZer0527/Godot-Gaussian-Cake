"""Isolated raw-model preparation, editor wiring, and generated-resource export checks."""
from pathlib import Path
import json
import math
import shutil
import struct
import tempfile


def write_fixtures(directory):
    """Small real meshes/captures with deliberately awkward, literal file paths."""
    directory.mkdir(parents=True)
    vertices = [(-0.8, 0, -0.6), (0.8, 0, -0.6), (0, 0, 0.8), (0, 1.4, 0)]
    triangles = [(0, 2, 1), (0, 1, 3), (1, 2, 3), (2, 0, 3)]
    positions = b''.join(struct.pack('<3f', *v) for v in vertices)
    indices = b''.join(struct.pack('<3H', *face) for face in triangles)
    binary = positions + indices
    document = {
        'asset': {'version': '2.0'}, 'scene': 0,
        'scenes': [{'nodes': [0]}], 'nodes': [{'mesh': 0}],
        'buffers': [{'byteLength': len(binary)}],
        'bufferViews': [
            {'buffer': 0, 'byteOffset': 0, 'byteLength': len(positions), 'target': 34962},
            {'buffer': 0, 'byteOffset': len(positions), 'byteLength': len(indices), 'target': 34963},
        ],
        'accessors': [
            {'bufferView': 0, 'componentType': 5126, 'count': 4, 'type': 'VEC3',
             'min': [-0.8, 0, -0.6], 'max': [0.8, 1.4, 0.8]},
            {'bufferView': 1, 'componentType': 5123, 'count': 12, 'type': 'SCALAR'},
        ],
        'materials': [{'pbrMetallicRoughness': {'baseColorFactor': [0.1, 0.9, 0.25, 1]}}],
        'meshes': [{'primitives': [{'attributes': {'POSITION': 0}, 'indices': 1, 'material': 0}]}],
    }
    encoded = json.dumps(document).encode('utf-8')
    encoded += b' ' * (-len(encoded) % 4)
    binary += b'\0' * (-len(binary) % 4)
    source = directory / 'Source ü ; $ & shape.glb'
    source.write_bytes(struct.pack('<III', 0x46546C67, 2, 28 + len(encoded) + len(binary))
                       + struct.pack('<II', len(encoded), 0x4E4F534A) + encoded
                       + struct.pack('<II', len(binary), 0x004E4942) + binary)
    external_buffer = directory/'Geometry ü & $.bin'
    external_buffer.write_bytes(binary)
    document['buffers'][0]['uri'] = external_buffer.name
    external_json = json.dumps(document, ensure_ascii=False).encode('utf-8')
    external_json += b' ' * (-len(external_json) % 4)
    external_source = directory/'External geometry ü.glb'
    external_source.write_bytes(struct.pack('<III',0x46546C67,2,20+len(external_json))
                                + struct.pack('<II',len(external_json),0x4E4F534A)+external_json)
    target = directory / 'Target ü ; $ & shape.ply'
    header = ('ply\nformat ascii 1.0\nelement vertex 4\nproperty float x\nproperty float y\n'
              'property float z\nproperty uchar red\nproperty uchar green\nproperty uchar blue\n'
              'element face 4\nproperty list uchar int vertex_indices\nend_header\n')
    target.write_text(header + ''.join(f'{x * 0.6} {y * 1.5} {z} 230 60 40\n' for x, y, z in vertices)
                      + ''.join('3 ' + ' '.join(map(str, face)) + '\n' for face in triangles), encoding='utf-8')
    uppercase_source = directory/'Uppercase source.GLB'
    uppercase_target = directory/'Uppercase target.PLY'
    shutil.copy2(source,uppercase_source)
    shutil.copy2(target,uppercase_target)
    broken = directory / 'Malformed model.ply'
    broken.write_text('not a PLY model\n', encoding='utf-8')
    captures = []
    for offset in (0, 1):
        capture = directory / f'Capture {offset} with SH.ply'
        properties = ['x', 'y', 'z', 'f_dc_0', 'f_dc_1', 'f_dc_2'] + [f'f_rest_{i}' for i in range(45)]
        properties += ['opacity', 'scale_0', 'scale_1', 'scale_2', 'rot_0', 'rot_1', 'rot_2', 'rot_3']
        capture_header = 'ply\nformat binary_little_endian 1.0\nelement vertex 256\n'
        capture_header += ''.join(f'property float {name}\n' for name in properties) + 'end_header\n'
        data = bytearray(capture_header.encode('ascii'))
        for index in range(256):
            angle = index * math.pi * (3 - math.sqrt(5))
            z = 1 - 2 * (index + 0.5) / 256
            radius = math.sqrt(1 - z*z)
            values = [radius * math.cos(angle), z * (1 + offset * 0.3), radius * math.sin(angle)]
            values += [0.1 + offset * 0.2, 0.6 - offset * 0.4, 0.1] + [0.03] * 45
            values += [3.0, -2.8, -2.8, -2.8, 1, 0, 0, 0]
            data += struct.pack('<' + 'f' * len(values), *values)
        capture.write_bytes(data)
        captures.append(str(capture))
    return {'source_path': str(source), 'target_path': str(target), 'malformed_path': str(broken),
            'capture_source': captures[0], 'capture_target': captures[1],
            'external_source_path':str(external_source),'external_buffer_path':str(external_buffer),
            'uppercase_source_path':str(uppercase_source),'uppercase_target_path':str(uppercase_target)}


def verify_preparation(root, output, cli, run):
    root, output = Path(root), Path(output)
    project = Path(tempfile.mkdtemp(prefix='preparation-ü-', dir=output))
    shutil.copytree(root/'addons'/'gaussian_cake', project/'addons'/'gaussian_cake')
    inputs = write_fixtures(project.parent/(project.name + '-inputs ü ; $ &'))
    inputs['cli_path'] = str(Path(cli).resolve())
    (project/'test-inputs.json').write_text(json.dumps(inputs, ensure_ascii=False), encoding='utf-8')
    config = '''config_version=5
[application]
config/name="Gaussian Cake preparation integration"
run/main_scene="res://preparation_smoke.tscn"
[editor_plugins]
enabled=PackedStringArray("res://addons/gaussian_cake/plugin.cfg")
[rendering]
renderer/rendering_method="gl_compatibility"
'''
    (project/'project.godot').write_text(config, encoding='utf-8')
    for scene_name in ('preparation_smoke.tscn', 'preparation_workspace.tscn'):
        (project/scene_name).write_text('[gd_scene format=3]\n[node name="PreparationPreview" type="Node3D"]\n', encoding='utf-8')
    shutil.copy2(root/'tests'/'preparation_pack_runner.gd', project/'preparation_smoke.gd')
    run(project, 'preparation-import', '--editor', '--import', '--quit')
    shutil.copytree(root/'tests'/'editor_preparation_probe', project/'addons'/'gc_preparation_probe')
    run(project, 'preparation-probe-parse', '--script', 'res://addons/gc_preparation_probe/probe.gd', '--check-only')
    (project/'project.godot').write_text(config.replace(
        '"res://addons/gaussian_cake/plugin.cfg")',
        '"res://addons/gaussian_cake/plugin.cfg", "res://addons/gc_preparation_probe/plugin.cfg")'), encoding='utf-8')
    run(project, 'preparation-editor', '--editor')
    assert (project/'editor-preparation-result.txt').read_text().strip() == '0', 'Preparation probe did not finish'
    (project/'project.godot').write_text(config, encoding='utf-8')
    run(project, 'preparation-generated-runtime')
    # No include_filter: the addon must include generated manifest JSON itself.
    preset = '''[preset.0]
name="Desktop PCK"
platform="Windows Desktop"
runnable=true
export_filter="all_resources"
include_filter=""
exclude_filter="addons/gc_preparation_probe/*,addons/gaussian_cake/editor/*,addons/gaussian_cake/plugin.gd,test-inputs.json,out/*"
script_export_mode=2
[preset.0.options]
binary_format/architecture="x86_64"
'''
    (project/'export_presets.cfg').write_text(preset, encoding='utf-8')
    pack = output/'prepared-game.pck'
    run(project, 'preparation-export', '--editor', '--export-pack', 'Desktop PCK', str(pack))
    empty = Path(tempfile.mkdtemp(prefix='preparation-pack-launch-', dir=output))
    run(empty, 'preparation-pack-runtime', '--main-pack', str(pack), '--', '--expect-pack')
    print(f'Preparation test project: {project}', flush=True)
    return project
