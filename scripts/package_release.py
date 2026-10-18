"""Collect evidence and create a clean, hash-manifested release (stdlib only)."""
from pathlib import Path
import difflib
import hashlib
import json
import shutil
import zipfile

root = Path(__file__).resolve().parents[1]
reports = root / 'reports'
reports.mkdir(exist_ok=True)
latest = sorted((root / 'build/icarus_diagnostic').glob('*/results.json'))[-1]
project_results = json.loads(latest.read_text(encoding='utf-8-sig'))
cpu_results = json.loads((reports / 'cpu_diagnostic/results.json').read_text(encoding='utf-8-sig'))
assert len(project_results) == 7 and all(r['assertions_passed'] for r in project_results)
assert len(cpu_results) == 12 and all(r['simulation_pass'] for r in cpu_results)
for folder in ('project_diagnostic', 'vivado', 'xsim_attempt'):
    (reports / folder).mkdir(exist_ok=True)
for p in latest.parent.iterdir():
    if p.suffix in ('.log', '.json'):
        shutil.copy2(p, reports / 'project_diagnostic' / p.name)
for p in (root / 'build/vivado').glob('*.rpt'):
    shutil.copy2(p, reports / 'vivado' / p.name)
shutil.copy2(root / 'build_vivado.log', reports / 'vivado/build.log')
for p in (root / 'build/xsim').glob('*.log'):
    shutil.copy2(p, reports / 'xsim_attempt' / p.name)
if (root / '.cpu_xsim/compile.log').exists():
    shutil.copy2(root / '.cpu_xsim/compile.log', reports / 'xsim_attempt/cpu_compile.log')
for p in (root / '.cpu_xsim').glob('*.elab.log'):
    shutil.copy2(p, reports / 'xsim_attempt' / ('cpu_' + p.name))
shutil.copy2(root / 'build/sim/puyo_video.png', reports / 'puyo_video.png')

# Unified textual comparison preserves the implementation history.
old_core = next((root / 'baseline_v3').rglob('TD8_RISCV_V2_Core.v'))
pairs = [(old_core, root / 'rtl/cpu/TD8_RISCV_V31_Core.v')]
for name in ('ProgramCounterV2.v', 'RegisterFileV2.v'):
    pairs.append((next((root/'baseline_v3').rglob(name)), root/'rtl/cpu'/name))
patch = []
for a, b in pairs:
    patch.extend(difflib.unified_diff(a.read_text(encoding='utf-8-sig').splitlines(True),
                                    b.read_text(encoding='utf-8-sig').splitlines(True),
                                    fromfile=a.relative_to(root).as_posix(),
                                    tofile=b.relative_to(root).as_posix()))
(root / 'docs/CPU_v3_to_v31.diff').write_text(''.join(patch), encoding='utf-8')

selected = [root/'README.md', root/'BASELINE_MANIFEST.json']
for folder in ('baseline_v3', 'rtl', 'firmware', 'sim', 'constrs', 'scripts', 'docs', 'reports'):
    selected.extend(p for p in (root/folder).rglob('*') if p.is_file()
                    and p.suffix not in ('.vvp', '.pyc') and '__pycache__' not in p.parts)
bit = root/'build/vivado/TD8_RISCV_PUYO_TOP.bit'
assert bit.exists(), 'No final bitstream'
assert 'PASS: synthesis, place/route, setup/hold, bitstream generation' in (root/'build_vivado.log').read_text()
assert 'CRITICAL WARNING:' not in (root/'build_vivado.log').read_text()
assert 'REQP-1839' not in (root/'build/vivado/drc.rpt').read_text()
selected.append(bit)
selected = sorted(set(selected))
manifest = {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in selected}
manifest_path = root/'RELEASE_SHA256.json'
manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
selected.append(manifest_path)
archive = root.parent / (root.name + '.zip')
with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for p in selected:
        z.write(p, root.name + '/' + p.relative_to(root).as_posix())
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    for name, expected in manifest.items():
        assert hashlib.sha256(z.read(root.name+'/'+name)).hexdigest() == expected
print(json.dumps({'archive': str(archive), 'files': len(selected), 'bytes': archive.stat().st_size,
                  'project_benches': len(project_results), 'cpu_benches': len(cpu_results),
                  'compiler_clean': all(r['clean_compile'] for r in project_results+cpu_results)}, indent=2))
