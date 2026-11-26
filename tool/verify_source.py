"""Structural checks only; does not substitute for flutter analyze/test/build.
Authoring checks: pip install tree-sitter tree-sitter-dart pyyaml
"""
from pathlib import Path
import json, plistlib, py_compile, xml.etree.ElementTree as ET
from tree_sitter import Language, Parser
import tree_sitter_dart
import yaml

root=Path(__file__).resolve().parents[1]
parser=Parser(Language(tree_sitter_dart.language()))
errors=[]
files=list((root/'lib').rglob('*.dart'))+list((root/'test').rglob('*.dart'))
for path in files:
    tree=parser.parse(path.read_bytes())
    if tree.root_node.has_error:
        errors.append(str(path.relative_to(root)))
for path in root.rglob('*.json'):
    json.loads(path.read_text())
for path in root.rglob('*.xml'):
    ET.parse(path)
with (root/'platform_config/ios/Runner.entitlements').open('rb') as stream:
    plistlib.load(stream)
spec=yaml.safe_load((root/'pubspec.yaml').read_text())
assert spec['name']=='fieldforce_hrms'
assert 'flutter_background_geolocation' not in spec['dependencies']
assert (root/'platform_config/android/DutyLocationService.kt').exists()
for script in ('bootstrap.py','verify_source.py'):
    py_compile.compile(str(root/'tool'/script),doraise=True)
if errors:
    raise SystemExit('Dart syntax errors: '+', '.join(errors))
print(f'PASS: {len(files)} Dart files parsed; JSON/XML/plist/YAML valid; Python scripts compile.')
print('NOT RUN: Flutter dependency resolution, Dart analyzer, Flutter tests, APK/IPA builds, physical-device tests.')
