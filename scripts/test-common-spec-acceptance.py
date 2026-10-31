#!/usr/bin/env python3
"""Record Stage 6 supporting evidence; never certify physical-device acceptance."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--spec', type=Path, required=True)
    parser.add_argument('--scope', choices=['host', 'builds', 'ui', 'all'], default='all')
    parser.add_argument('--output', type=Path, required=True, help='New directory for this run')
    parser.add_argument('--iphone-simulator')
    parser.add_argument('--ipad-simulator')
    parser.add_argument('--tv-simulator')
    args = parser.parse_args()
    reference = json.loads((ROOT / 'tests/common-spec-reference.json').read_text())
    specification = args.spec.read_bytes()
    digest = hashlib.sha256(specification).hexdigest()
    if digest != reference['specification_sha256']:
        parser.error('Specification changed; review the reference before running acceptance')
    env = dict(os.environ)
    env.setdefault('DEVELOPER_DIR', '/Applications/Xcode.app/Contents/Developer')

    def capture(command):
        return subprocess.check_output(command, cwd=ROOT, env=env, text=True).strip()

    simulators = [('iphone', args.iphone_simulator), ('ipad', args.ipad_simulator), ('tv', args.tv_simulator)]
    if args.scope == 'ui' and not any(identifier for _, identifier in simulators):
        parser.error('UI scope needs at least one explicitly selected, booted simulator')
    if args.scope in ('ui', 'all') and any(identifier for _, identifier in simulators):
        devices = json.loads(capture(['xcrun', 'simctl', 'list', 'devices', '--json']))['devices']
        booted = {device['udid'] for runtime in devices.values() for device in runtime if device['state'] == 'Booted'}
        for name, identifier in simulators:
            if identifier and identifier not in booted:
                parser.error(f'{name} is not booted; this runner never boots or erases devices')
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    (output / 'specification.md').write_bytes(specification)
    build_root = Path('/tmp') / ('ContinuousPlayer-stage6-' + hashlib.sha256(str(output).encode()).hexdigest()[:10])
    report = {
        'schema': 1, 'started_at_utc': datetime.now(timezone.utc).isoformat(),
        'implementation_head': capture(['git', 'rev-parse', 'HEAD']),
        'working_tree': capture(['git', 'status', '--short']),
        'working_diff_sha256': hashlib.sha256(capture(['git', 'diff', 'HEAD']).encode()).hexdigest(),
        'reference': reference, 'specification_sha256': digest,
        'xcode': capture(['xcodebuild', '-version']), 'macos': capture(['sw_vers']),
        'physical_acceptance': '未確認; host/build/Simulator evidence is not physical-input acceptance',
        'selected_simulators': dict(simulators), 'checks': [],
    }
    # Include untracked test/runner contents in reproducibility evidence.
    files = capture(['git', 'ls-files', '--cached', '--others', '--exclude-standard']).splitlines()
    report['source_sha256'] = {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest()
                               for p in files if (ROOT / p).is_file()}
    checks = []
    if args.scope in ('host', 'all'):
        for name in ('enumeration', 'playback', 'playback-integration', 'dlna', 'playback-session',
                     'file-selection', 'playback-recovery', 'playback-input', 'playback-chrome', 'common-spec-media'):
            checks.append((name, ['sh', f'scripts/test-{name}.sh'], {}, 240, False))
        checks.append(('fixture-server', [sys.executable, 'tests/test_common_spec_fixture_server.py'], {}, 90, False))
    if args.scope in ('builds', 'all'):
        for name, scheme, destination in (
            ('ios-build', 'ContinuousPlayer_for_iOS', 'generic/platform=iOS Simulator'),
            ('tvos-build', 'ContinuousPlayer_for_tvOS', 'generic/platform=tvOS Simulator'),
        ):
            checks.append((name, ['xcodebuild', '-project', 'ContinuousPlayer_for_iOS.xcodeproj', '-scheme', scheme,
                '-configuration', 'Debug', '-destination', destination, '-derivedDataPath', str(build_root / name),
                'build', 'CODE_SIGNING_ALLOWED=NO'], {}, 600, False))
        checks.append(('catalyst-build', ['bash', 'script/build_and_run.sh', '--build-only'],
                       {'BUILD_DIR': str(build_root / 'catalyst')}, 600, False))
        bundle = build_root / 'catalyst/Build/Products/Debug-maccatalyst/ContinuousPlayer.app/Contents/PlugIns/MacPlaybackLifecycle.bundle'
        checks.append(('mac-lifecycle', ['sh', 'scripts/test-mac-lifecycle.sh', str(bundle)], {}, 90, False))
    if args.scope in ('ui', 'all'):
        for name, identifier in simulators:
            if not identifier:
                continue
            tv = name == 'tv'
            checks.append((name + '-acceptance-ui', ['sh', 'scripts/test-tvos-ui.sh' if tv else 'scripts/test-dlna-ui.sh',
                'validation/common-spec/media/Fixture OP.mp4'],
                {'SIMULATOR_ID': identifier, 'DERIVED_DATA_PATH': str(build_root / name),
                 'DLNA_FIXTURE_PORT': '18765' if tv else '18767',
                 'ONLY_TESTING': 'TVUITests/Stage6TVAcceptanceUITests' if tv else 'DeviceUITests/Stage6AcceptanceUITests'},
                900, True))

    def save():
        (output / 'results.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')

    save()
    for name, command, overrides, timeout, ui in checks:
        print(f'Running {name}', flush=True)
        log = output / (name + '.log')
        started = datetime.now(timezone.utc)
        with log.open('w') as handle:
            process = subprocess.Popen(command, cwd=ROOT, env=env | overrides, stdout=handle,
                                       stderr=subprocess.STDOUT, start_new_session=True)
            try:
                code = process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL); process.wait()
                code = 124
        text = log.read_text(errors='replace')
        counts = re.findall(r'Executed (\d+) tests?, with (\d+) failures?', text)
        executed = max((int(n) for n, _ in counts), default=0)
        passed = code == 0 and (not ui or (executed > 0 and '** TEST SUCCEEDED **' in text))
        report['checks'].append({'name': name, 'command': command, 'environment': overrides,
            'exit_code': code, 'passed': passed, 'ui_test_count': executed if ui else None,
            'result_bundles': re.findall(r'^\s*(/.*\.xcresult)\s*$', text, re.M),
            'elapsed_seconds': (datetime.now(timezone.utc) - started).total_seconds(), 'log': str(log)})
        save()
        print(f'{name}: {"PASS" if passed else "FAIL"}, tests={executed if ui else "n/a"}', flush=True)
    report['finished_at_utc'] = datetime.now(timezone.utc).isoformat()
    save()
    return int(any(not check['passed'] for check in report['checks']))


if __name__ == '__main__':
    sys.exit(main())
