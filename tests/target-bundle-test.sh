#!/bin/sh
# platform: host-agnostic
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; export ROOT
: "${SHIPYARD_SCRIPTS:?need shipyard}"
python3 - <<'PY'
import os, pathlib, shutil, subprocess, tempfile
root=pathlib.Path(os.environ['ROOT'])
with tempfile.TemporaryDirectory() as tmp:
 t=pathlib.Path(tmp); tc=t/'tc'; (tc/'bin').mkdir(parents=True)
 scripts=t/'scripts';shutil.copytree(os.environ['SHIPYARD_SCRIPTS'],scripts)
 sdk=t/'sdk';(sdk/'usr/include/c++/v1').mkdir(parents=True)
 (scripts/'fetch_sdk.sh').write_text('#!/bin/sh\nprintf "%s\\n" "'+str(sdk)+'"\n')
 compiler=tc/'bin/clang++'
 compiler.write_text('''#!/usr/bin/env python3
import os,sys,pathlib
args=sys.argv[1:]; output=pathlib.Path(args[args.index('-o')+1])
if '-emit-llvm' in args:
 alignment=16 if '--target=x86_64-apple-macos10.14' in args else 8
 output.write_text(('call ptr @__cxa_begin_catch(\\nload i128, ptr %v, align '+str(alignment)+'\\n')*2)
else:
 output.write_text('#!/bin/sh\\ntouch "'+os.environ['EXECUTION_MARKER']+'"\\necho caught 5\\n')
 output.chmod(0o755)
''');compiler.chmod(0o755)
 (tc/'bin/clang').symlink_to('clang++')
 (scripts/'assert_binary_compatible.sh').write_text('#!/bin/sh\nexit 0\n')
 env=dict(os.environ,TC=str(tc),SHIPYARD_SCRIPTS=str(scripts),TEST_PHASE='build',TEST_OUT=str(t/'bundle'),EXECUTION_MARKER=str(t/'executed'))
 r=subprocess.run(['sh',str(root/'tests/catch-align-test.sh')],env=env,capture_output=True,text=True)
 assert r.returncode==0,(r.stdout,r.stderr)
 assert not (t/'executed').exists(),'build phase executed a target binary on the host'
 assert (t/'bundle/catch-align/r').is_file(),'build phase did not retain target binary'
 assert (t/'bundle/catch-align/run.sh').is_file(),'no portable target runner'
 assert (t/'bundle/catch-align/wide').is_file(),'build phase did not retain aligned-class witness'
 # Exercise the saved runner with controlled outputs, without executing Mach-O on this host.
 case=t/'bundle/catch-align'
 (case/'r').write_text('#!/bin/sh\necho caught 5\n')
 (case/'wide').write_text('#!/bin/sh\necho wrong\n')
 r=subprocess.run(['sh',str(case/'run.sh')],capture_output=True,text=True)
 assert r.returncode!=0,'aligned-class runtime failure was ignored'
 (case/'wide').write_text('#!/bin/sh\n[ "$1" = wide ] || exit 2\necho caught 6\n')
 r=subprocess.run(['sh',str(case/'run.sh')],capture_output=True,text=True)
 assert r.returncode==0,(r.stdout,r.stderr)

 r=subprocess.run(['sh',str(root/'tests/cxxabi-interop-test.sh')],env=env,capture_output=True,text=True)
 assert r.returncode==0,(r.stdout,r.stderr)
 assert not (t/'executed').exists(),'interop build phase executed target code'
 assert (t/'bundle/cxxabi/interop-static').is_file()
 r=subprocess.run(['sh',str(root/'tests/profile-runtime-test.sh')],env=env,capture_output=True,text=True)
 assert r.returncode==0,(r.stdout,r.stderr)
 assert not (t/'executed').exists(),'profile build phase executed target code'
 assert (t/'bundle/profile/instr').is_file()
 runner=root/'tests/target/runner.sh'
 r=subprocess.run(['sh',str(runner),str(t/'bundle')],capture_output=True,text=True)
 assert r.returncode!=0,'runner accepted Linux or incomplete bundle'
 tools=t/'tools';tools.mkdir()
 uname=tools/'uname';uname.write_text('#!/bin/sh\ncase "$1" in -s) echo Darwin ;; -m) echo x86_64 ;; esac\n');uname.chmod(0o755)
 runenv=dict(os.environ,PATH=str(tools)+':'+os.environ['PATH'])
 def run_target():
  return subprocess.run(['sh',str(runner),str(t/'bundle')],env=runenv,capture_output=True,text=True)
 r=run_target();assert r.returncode!=0 and 'missing required weak-bind' in r.stderr,(r.stdout,r.stderr)
 for case in ['catch-align','weak-bind','cxxabi','profile']:
  d=t/'bundle'/case;d.mkdir(exist_ok=True);(d/'run.sh').write_text('#!/bin/sh\nexit 0\n')
 (t/'bundle/profile/run.sh').write_text('#!/bin/sh\nexit 77\n')
 r=run_target();assert r.returncode!=0,'target skip treated as success'
 (t/'bundle/profile/run.sh').write_text('#!/bin/sh\nexit 0\n')
 r=run_target();assert r.returncode==0,(r.stdout,r.stderr)
 assert (t/'bundle/results.txt').read_text()=='PASS catch-align\nPASS weak-bind\nPASS cxxabi\nPASS profile\n'

print('PASS: build phase retains but does not execute target output')
PY
