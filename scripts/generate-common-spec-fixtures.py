#!/usr/bin/env python3
"""Generate synthetic media for the common-spec acceptance scenarios."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=Path('validation/common-spec/media'))
    parser.add_argument('--duration', type=int, default=90)
    args = parser.parse_args()
    if args.duration < 45:
        parser.error('--duration must be at least 45 seconds for 30-second restoration tests')
    ffmpeg = shutil.which(os.environ.get('FFMPEG', 'ffmpeg'))
    ffprobe = shutil.which(os.environ.get('FFPROBE', 'ffprobe'))
    if not ffmpeg or not ffprobe:
        parser.error('ffmpeg and ffprobe are required (or set FFMPEG / FFPROBE)')
    args.output.mkdir(parents=True, exist_ok=True)
    for filename, color, frequency in [('Fixture OP.mp4', 'navy', 440), ('Fixture ED.mp4', 'darkgreen', 660)]:
        subprocess.run([ffmpeg, '-hide_banner', '-loglevel', 'error', '-y',
                        '-f', 'lavfi', '-i', f'color=c={color}:s=320x180:r=30',
                        '-f', 'lavfi', '-i', f'sine=frequency={frequency}:sample_rate=48000',
                        '-t', str(args.duration), '-c:v', 'libx264', '-preset', 'veryfast',
                        '-pix_fmt', 'yuv420p', '-g', '30', '-c:a', 'aac', '-b:a', '64k',
                        '-movflags', '+faststart', str(args.output / filename)], check=True)
    subprocess.run([ffmpeg, '-hide_banner', '-loglevel', 'error', '-y', '-f', 'lavfi',
                    '-i', 'sine=frequency=880:sample_rate=48000', '-t', str(args.duration),
                    '-c:a', 'pcm_s16le', str(args.output / 'Audio OP.wav')], check=True)
    (args.output / 'Corrupt OP.mp4').write_bytes(b'intentionally invalid common-spec media\n')
    nested = args.output / 'Other Folder'
    nested.mkdir(exist_ok=True)
    shutil.copyfile(args.output / 'Fixture ED.mp4', nested / 'Other OP.mp4')
    # The same stem with two formats exposes missing collision badges.
    shutil.copyfile(args.output / 'Fixture OP.mp4', args.output / 'Fixture OP.m4v')
    files = []
    for path in sorted(args.output.rglob('*')):
        if not path.is_file() or path.name == 'manifest.json':
            continue
        entry = {'path': str(path.relative_to(args.output)), 'bytes': path.stat().st_size,
                 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
        if path.name != 'Corrupt OP.mp4':
            result = subprocess.run([ffprobe, '-v', 'error', '-show_entries',
                                     'format=duration:stream=codec_type,codec_name', '-of', 'json',
                                     str(path)], check=True, capture_output=True, text=True)
            info = json.loads(result.stdout)
            entry['duration'] = float(info['format']['duration'])
            entry['streams'] = info['streams']
            if entry['duration'] < args.duration - 0.1:
                raise RuntimeError(f'{path}: generated duration is shorter than requested')
        files.append(entry)
    manifest = {'schema': 1, 'duration': args.duration, 'synthetic': True, 'files': files}
    (args.output / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    print(f'Generated and probed {len(files)} files: {args.output / "manifest.json"}')


if __name__ == '__main__':
    main()
