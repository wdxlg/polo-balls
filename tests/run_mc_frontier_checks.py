"""Run finite Godot checks with a process-level exit code (also works with Windows GUI builds).
Example: python tests/run_mc_frontier_checks.py --godot <godot.exe> --test test_mc_frontier
"""
from pathlib import Path
import argparse
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser()
p.add_argument('--godot', required=True)
p.add_argument('--test', action='append', dest='tests')
a = p.parse_args()
names = a.tests or ['test_mc_frontier', 'test_mc_moss', 'test_mc_moss_consumption', 'test_mc_moss_presentation', 'test_mc_minecart', 'test_mc_minecart_directions', 'test_mc_frontier_live', 'test_mc_minecart_live', 'test_character_name_translations', 'test_mc_armor_summaries']
failures = []
for name in names:
    if not re.fullmatch(r'test_[A-Za-z0-9_]+', name):
        raise SystemExit('Invalid test name')
    print('RUNNING '+name, flush=True)
    try:
        result = subprocess.run([a.godot, '--headless', '--path', str(ROOT), '--script', 'res://tests/'+name+'.gd', '--log-file', str(ROOT/(name+'.log'))], cwd=ROOT, capture_output=True, encoding='utf-8', errors='replace', timeout=100)
        output = result.stdout+'\n'+result.stderr
        (ROOT/'tests'/(name+'_captured.log')).write_text(output, encoding='utf-8')
        for line in output.splitlines():
            if re.search(r'RESULT|CONTRACTS:|LIVE[: ]|SUMMARY|PROBE|FAIL:|ERROR:|Script Error|at:|\[[0-9]+\]', line):
                print(line, flush=True)
        bad = result.returncode != 0 or bool(re.search(r'(?m)^(?:SCRIPT ERROR:|ERROR:)', output))
        print(f'TEST_EXIT {name}: process={result.returncode}, errors={bad}', flush=True)
        if bad:
            failures.append(name)
    except subprocess.TimeoutExpired:
        failures.append(name)
        print('TEST_TIMEOUT '+name, flush=True)
print(f'CHECK_RUNNER: {len(names)-len(failures)}/{len(names)} test scripts passed; failures={failures}', flush=True)
sys.exit(1 if failures else 0)
