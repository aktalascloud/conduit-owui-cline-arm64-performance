import hashlib,json,os,platform,subprocess
from pathlib import Path
r=Path(__file__).resolve().parents[1]
p=json.loads((r/'.avx1/native-arm64.json').read_text())
t=json.loads((r/'.avx1/toolchains.json').read_text())
tools=platform.python_version()+os.environ.get('JAVA_HOME','')+subprocess.check_output(['cmake','--version'],text=True)
prefix='native-arm64-v2-'+os.environ.get('GITHUB_REPOSITORY','local').replace('/','-')+'-'+t['android']['ndk'].split(';')[1]+'-'+p['onnx']['commit']+'-'+p['eigen']['commit']+'-'+hashlib.sha256(tools.encode()).hexdigest()[:12]
with open(os.environ['GITHUB_OUTPUT'],'a',encoding='utf-8') as f:f.write('prefix='+prefix+'\n')
