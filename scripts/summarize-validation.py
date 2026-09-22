"""Summarize measured probes without equating API success with visual/audio QA."""
import json,pathlib,re
root=pathlib.Path(__file__).resolve().parent.parent
text=(root/'validation/device-log.txt').read_text()
rows=[]
dataset='unknown'
for line in text.splitlines():
    if '列挙:' in line:
        dataset=line.split('列挙: ',1)[1].split(',')[0]
    if '素材: ' in line:
        m=re.search(r'素材: (.*), isPlayable=(true|false), duration=([^,]+), codecs=(.*)',line)
        if m:
            rows.append(dict(dataset=dataset,name=m[1],playable=m[2]=='true',duration=float(m[3]),codecs=json.loads(m[4]),progressed=False,seekReached=False,decodedFrame=None))
    elif '再生計測:' in line and rows:
        m=re.search(r'elapsed=([^,]+), status=(\d+), error=(.*)',line)
        if m:
            rows[-1]['elapsed']=float(m[1]); rows[-1]['progressed']=float(m[1])>0.5 and m[2]=='1' and m[3]=='nil'
    elif '映像デコード計測:' in line and rows:
        rows[-1]['decodedFrame']='pixelBuffer=true' in line
    elif 'シーク計測:' in line and rows:
        rows[-1]['seekReached']='reached=true' in line
errors=[line for line in text.splitlines() if '素材エラー:' in line]
summary=dict(measurements=rows,errors=errors,completedRuns=text.count('検証完了（'),note='API measurements only; not full-file playback, listening, or visual confirmation.')
(root/'validation/summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2))
for dataset in dict.fromkeys(r['dataset'] for r in rows):
    subset=[r for r in rows if r['dataset']==dataset]
    passed=sum(r['playable'] and r['progressed'] and r['seekReached'] and r['decodedFrame'] is not False for r in subset)
    print(f'{dataset}: {passed}/{len(subset)} measured samples passed')
print(f'Expected or unexpected asset errors: {len(errors)}; completed runs: {summary["completedRuns"]}')
