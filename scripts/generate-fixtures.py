"""Generate deterministic six-second synthetic media; requires ffmpeg on PATH or FFMPEG."""
import math, os, pathlib, shutil, struct, subprocess, wave
root = pathlib.Path(__file__).resolve().parent.parent / 'validation' / 'fixtures'
root.mkdir(parents=True, exist_ok=True)
ffmpeg = os.environ.get('FFMPEG', 'ffmpeg')
wav = root / '01_pcm.wav'
with wave.open(str(wav), 'w') as w:
    w.setparams((2, 2, 48000, 0, 'NONE', 'not compressed'))
    w.writeframes(b''.join(struct.pack('<hh', int(3500*math.sin(2*math.pi*440*i/48000)), int(3500*math.sin(2*math.pi*660*i/48000))) for i in range(48000*6)))
for name, codec in [('02_aac.m4a','aac'), ('03_adts.aac','aac'), ('04_lossless.flac','flac'), ('05_alac.m4a','alac'), ('06_opus.opus','libopus'), ('07_vorbis.ogg','libvorbis'), ('08_mpeg.mp3','libmp3lame')]:
    subprocess.run([ffmpeg,'-hide_banner','-loglevel','error','-y','-i',str(wav),'-c:a',codec,str(root/name)], check=True)
for name, codec in [('09_h264.mp4','libx264'), ('10_hevc.mp4','libx265')]:
    subprocess.run([ffmpeg,'-hide_banner','-loglevel','error','-y','-f','lavfi','-i','testsrc2=size=320x180:rate=30','-i',str(wav),'-t','6','-c:v',codec,'-pix_fmt','yuv420p','-tag:v','hvc1' if codec == 'libx265' else 'avc1','-c:a','aac',str(root/name)], check=True)
shutil.copyfile(root/'09_h264.mp4',root/'11_h264.m4v')
shutil.copyfile(wav, root/'12_uppercase.WAV')
shutil.copyfile(wav, root/'.hidden.wav')
(root/'._ignored.mp4').write_bytes(b'AppleDouble test placeholder')
(root/'ignored.txt').write_text('not a media file')
(root/'nested').mkdir(exist_ok=True)
shutil.copyfile(wav,root/'nested'/'not_scanned.wav')
(root/'99_corrupt.mp4').write_bytes(b'intentionally invalid media')
