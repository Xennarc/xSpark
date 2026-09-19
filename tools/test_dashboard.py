#!/usr/bin/env python3
"""Exercise the production dashboard with chart-object doubles, not MT5.

Optionally export drawing commands for the illustrative preview:
  python3 tools/test_dashboard.py --scene /tmp/xspark-scenes.txt
"""
from pathlib import Path
import argparse
import os
import re
import subprocess
import tempfile
from mql_adapter import PREAMBLE, adapt

ROOT = Path(__file__).resolve().parents[1]
FILES = [
    'Strategy/StrategyInterface.mqh', 'Strategy/ScoreBotTypes.mqh',
    'Core/UserMessages.mqh', 'Core/Logger.mqh',
    'UI/DashboardLayout.mqh', 'UI/Dashboard.mqh',
]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--scene', type=Path)
    args = parser.parse_args()
    body = PREAMBLE + (ROOT / 'tools/dashboard_stubs.hpp').read_text()
    for file in FILES:
        body += adapt((ROOT / 'MQL5/Include/XSpark' / file).read_text())
    body = re.sub(r"C'(\d+),(\d+),(\d+)'", lambda m: str((int(m[1]) << 16) | (int(m[2]) << 8) | int(m[3])), body)
    for file in ['TestDashboardLayout.mq5', 'TestDashboardExperience.mq5']:
        body += adapt((ROOT / 'MQL5/Scripts/Tests' / file).read_text())
    body += (ROOT / 'tools/dashboard_tests.hpp').read_text()
    with tempfile.TemporaryDirectory(prefix='xspark-dashboard-') as tmp:
        source, exe = Path(tmp) / 'dashboard.cpp', Path(tmp) / 'dashboard'
        source.write_text(body)
        subprocess.run(['g++', '-std=c++17', '-Wall', '-Wextra', '-Werror', '-pedantic',
                        '-fsanitize=address,undefined', '-g', str(source), '-o', str(exe)], check=True)
        result = subprocess.run([str(exe)], text=True, capture_output=True,
                                env={**os.environ, 'ASAN_OPTIONS': 'detect_leaks=0'})
        lines = result.stdout.splitlines()
        print('\n'.join(line for line in lines if not line.startswith(('OBJECT ', 'SCENE '))))
        if result.stderr:
            print(result.stderr)
        result.check_returncode()
        if args.scene:
            args.scene.write_text('\n'.join(line for line in lines if line.startswith(('OBJECT ', 'SCENE ')))+'\n')

if __name__ == '__main__':
    main()
