"""Headless tests, clean install, editor reimport/lifecycle/preview, and exported PCK.

python tools/verify.py --godot /path/to/godot
Artifacts and isolated projects are retained under out/ for diagnosis.
"""
import argparse
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--godot', required=True)
parser.add_argument('--cli', help='Gaussian Cake CLI executable; enables raw-model preparation integration tests')
args = parser.parse_args()
godot = str(Path(args.godot).resolve()) if Path(args.godot).exists() else args.godot
root = Path(__file__).resolve().parents[1]
output = root / 'out'
output.mkdir(exist_ok=True)
(output / '.gdignore').touch()

def run(project, name, *arguments):
    command = [godot, '--headless', '--path', str(project), '--log-file', str(output/f'{name}.log'), *arguments]
    result = subprocess.run(command, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=120)
    text = result.stdout + result.stderr
    (output/f'{name}-console.log').write_text(text, encoding='utf-8')
    if result.returncode or re.search(r'(?m)^(SCRIPT ERROR:|ERROR:|FAIL:|EDITOR TEST FAIL:)', text):
        print(text)
        raise SystemExit(f'{name} failed ({result.returncode})')
    print(f'PASS {name}', flush=True)
    for line in text.splitlines():
        if line.startswith('Gaussian Cake '):
            print('  '+line)

run(root, 'import', '--editor', '--import', '--quit')
RUNTIME_SUITES = (
    'run_tests', 'form_state_machine_test', 'form_manifest_test', 'forms_test', 'form_lifecycle_test', 'transport_maps_test',
    'slime_forms_test', 'slime_third_person_test', 'slime_pixel_test', 'splat_sort_test',
    'form_preview_runtime_test',
)
for suite in RUNTIME_SUITES:
    run(root, suite, '--script', f'res://tests/{suite}.gd')

clean = Path(tempfile.mkdtemp(prefix='clean-install-', dir=output))
shutil.copytree(root/'addons'/'gaussian_cake', clean/'addons'/'gaussian_cake')
assets = clean/'examples'/'assets'
assets.mkdir(parents=True)
for suffix in ('glb', 'gcsplat'):
    shutil.copy2(root/'examples'/'assets'/f'round_to_tall.{suffix}', assets)
# This tiny bundle exercises form/map import without copying either sample game.
shutil.copytree(
    root/'tests'/'fixtures'/'transport_maps', assets/'forms',
    ignore=shutil.ignore_patterns('*.import'),
)
(clean/'tests').mkdir()
shutil.copy2(root/'tests'/'run_tests.gd', clean/'tests'/'run_tests.gd')
shutil.copy2(root/'tests'/'pack_runner.gd', clean/'smoke.gd')
(clean/'smoke.tscn').write_text('''[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://smoke.gd" id="1"]
[node name="Smoke" type="Node3D"]
script = ExtResource("1")
''', encoding='utf-8')
project = '''config_version=5
[application]
config/name="Gaussian Cake isolated test"
run/main_scene="res://smoke.tscn"
[editor_plugins]
enabled=PackedStringArray("res://addons/gaussian_cake/plugin.cfg")
[rendering]
renderer/rendering_method="gl_compatibility"
'''
(clean/'project.godot').write_text(project, encoding='utf-8')
run(clean, 'clean-import', '--editor', '--import', '--quit')
run(clean, 'clean-runtime', '--script', 'res://tests/run_tests.gd')
run(clean, 'clean-form-runtime')

shutil.copytree(root/'tests'/'editor_probe', clean/'addons'/'gc_test_probe')
(clean/'project.godot').write_text(project.replace(
    '"res://addons/gaussian_cake/plugin.cfg")',
    '"res://addons/gaussian_cake/plugin.cfg", "res://addons/gc_test_probe/plugin.cfg")'), encoding='utf-8')
run(clean, 'editor-integration', '--editor')
assert (clean/'editor-test-result.txt').read_text().strip() == '0', 'Editor probe did not finish'
(clean/'project.godot').write_text(project, encoding='utf-8')
preset = (root/'export_presets.cfg').read_text(encoding='utf-8')
preset = preset.replace('exclude_filter="', 'exclude_filter="addons/gc_test_probe/*,')
preset = preset.replace('include_filter="', 'include_filter="examples/assets/forms/library.json,')
(clean/'export_presets.cfg').write_text(preset, encoding='utf-8')
pack = output/'clean-game.pck'
run(clean, 'export-pack', '--editor', '--export-pack', 'Desktop PCK', str(pack))
launch = Path(tempfile.mkdtemp(prefix='pack-launch-', dir=output))
# An empty directory prevents FileAccess falling back to original source files.
run(launch, 'pack-runtime', '--main-pack', str(pack), '--', '--expect-pack')

def verify_form_preview():
    """Exercise registered Inspector controls in a fresh editor, then run its saved scene."""
    preview = Path(tempfile.mkdtemp(prefix='form-preview-', dir=output))
    shutil.copytree(root/'addons'/'gaussian_cake', preview/'addons'/'gaussian_cake')
    fixtures = (
        (root/'tests'/'fixtures'/'transport_maps', 'tiny'),
        (root/'examples'/'slime'/'assets'/'forms', 'combined'),
        (root/'examples'/'transitions'/'assets', 'complex'),
    )
    for source, name in fixtures:
        shutil.copytree(source, preview/'assets'/name, ignore=shutil.ignore_patterns('*.import'))
    (preview/'tests').mkdir()
    shutil.copy2(root/'tests'/'form_preview_runtime_test.gd', preview/'tests')
    preview_project = '''config_version=5
[application]
config/name="Gaussian Cake Inspector integration"
[editor_plugins]
enabled=PackedStringArray("res://addons/gaussian_cake/plugin.cfg")
[rendering]
renderer/rendering_method="gl_compatibility"
'''
    (preview/'project.godot').write_text(preview_project, encoding='utf-8')
    run(preview, 'form-preview-import', '--editor', '--import', '--quit')
    shutil.copytree(root/'tests'/'editor_form_preview_probe', preview/'addons'/'gc_form_preview_probe')
    (preview/'project.godot').write_text(preview_project.replace(
        '"res://addons/gaussian_cake/plugin.cfg")',
        '"res://addons/gaussian_cake/plugin.cfg", "res://addons/gc_form_preview_probe/plugin.cfg")'), encoding='utf-8')
    run(preview, 'form-preview-editor', '--editor')
    assert (preview/'editor-form-preview-result.txt').read_text().strip() == '0', 'Form editor probe did not finish'
    (preview/'project.godot').write_text(preview_project, encoding='utf-8')
    run(preview, 'form-preview-saved-runtime', '--script', 'res://tests/form_preview_runtime_test.gd',
        '--', '--preview-saved=res://preview_saved.tscn')
    print(f'Inspector preview project: {preview}')

verify_form_preview()
if args.cli:
    from verify_preparation import verify_preparation
    verify_preparation(root, output, args.cli, run)
else:
    print('SKIP preparation integration (provide --cli /path/to/gc_cli)')
print(f'All verification passed. Isolated project: {clean}')
