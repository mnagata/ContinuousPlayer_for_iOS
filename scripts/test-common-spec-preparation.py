#!/usr/bin/env python3
"""Record the specification reference and rerunnable preparation baseline."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent


def output(command, env):
    result = subprocess.run(command, cwd=ROOT, env=env, text=True, capture_output=True)
    return (result.stdout + result.stderr).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--spec', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=ROOT / 'validation/common-spec/baseline')
    args = parser.parse_args()
    reference = json.loads((ROOT / 'tests/common-spec-reference.json').read_text())
    specification = args.spec.read_bytes()
    digest = hashlib.sha256(specification).hexdigest()
    if digest != reference['specification_sha256']:
        parser.error('specification content changed; review the reference before updating its hash')
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / 'specification.md').write_bytes(specification)
    env = dict(os.environ)
    env.setdefault('DEVELOPER_DIR', '/Applications/Xcode.app/Contents/Developer')
    checks = [
        ('enumeration', ['sh', 'scripts/test-enumeration.sh']),
        ('playback-state', ['sh', 'scripts/test-playback.sh']),
        ('playback-integration', ['sh', 'scripts/test-playback-integration.sh']),
        ('dlna', ['sh', 'scripts/test-dlna.sh']),
        ('common-spec-fixture', [sys.executable, 'tests/test_common_spec_fixture_server.py']),
        ('common-spec-media', ['sh', 'scripts/test-common-spec-media.sh']),
    ]
    report = {'schema': 1, 'started_at_utc': datetime.now(timezone.utc).isoformat(),
              'reference': reference, 'actual_specification_sha256': digest,
              'actual_implementation_head': output(['git', 'rev-parse', 'HEAD'], env),
              'working_tree': output(['git', 'status', '--short'], env),
              'xcode': output(['xcodebuild', '-version'], env),
              'swift': output(['xcrun', 'swift', '--version'], env),
              'scope': 'host baseline only; does not certify common-spec acceptance or device behavior',
              'checks': []}
    # Record each result immediately, so interruption does not erase prior evidence.
    def save():
        (args.output / 'results.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    save()
    for name, command in checks:
        log = args.output / (name + '.log')
        print(f'Running {name}; log: {log}', flush=True)
        started = datetime.now(timezone.utc)
        timed_out = False
        with log.open('w') as handle:
            process = subprocess.Popen(command, cwd=ROOT, env=env, stdout=handle,
                                       stderr=subprocess.STDOUT, start_new_session=True)
            try:
                code = process.wait(timeout=180)
            except subprocess.TimeoutExpired:
                timed_out, code = True, 124
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
        report['checks'].append({'name': name, 'command': command, 'exit_code': code,
                                 'timed_out': timed_out, 'log': str(log),
                                 'elapsed_seconds': (datetime.now(timezone.utc) - started).total_seconds()})
        save()
        print(f'{name}: {"PASS" if code == 0 else "FAIL"} ({code})', flush=True)
    report['finished_at_utc'] = datetime.now(timezone.utc).isoformat()
    save()
    return int(any(check['exit_code'] != 0 for check in report['checks']))


if __name__ == '__main__':
    sys.exit(main())
