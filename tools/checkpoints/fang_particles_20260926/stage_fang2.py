import subprocess,os
os.chdir(r'E:/godot/polo-balls')
def run(args,input=None):
    r=subprocess.run(args,capture_output=True,input=input)
    if r.returncode!=0: raise SystemExit(' '.join(args)+' FAILED '+r.stderr.decode('utf-8','replace')[:600])
    return r.stdout
def git(*a): return run(['git']+list(a)).decode('utf-8')
if git('diff','--cached','--stat').strip(): print('INDEX NOT EMPTY'); print(git('diff','--cached','--stat')); raise SystemExit(3)
FANG='scripts/effects/我的世界/唤魔尖牙.gd'; CTX='MCP_CONTEXT.md'
fang_edit=('''\t# Vanilla EvokerFangs emits twelve CRIT particles when its jaws close, spread
\t# across the jaw box (not stacked in one point), independent of actual damage.
\tABILITIES.critical_burst(self,global_position+Vector2(0,-10),get_instance_id(),{
\t\t"count":12, "radius":10.0,''','''\t# Vanilla EvokerFangs fires twelve CRIT sparks on jaw closure; one cast raises
\t# dozens of jaws here, so keep just a few per bite. They still spread across the
\t# jaw box instead of stacking, and fire whether or not the bite found a victim.
\tABILITIES.critical_burst(self,global_position+Vector2(0,-10),get_instance_id(),{
\t\t"count":4, "radius":10.0,''')
ctx_edit=('闭合瞬间按原版固定发射 12 颗 CRIT','闭合瞬间发射少量原版 CRIT 星芒（每口 4 颗，一圈数十张嘴不会糊屏）')
for path,(a,b) in {FANG:fang_edit,CTX:ctx_edit}.items():
    head=git('show','HEAD:'+path)
    crlf='\r\n' in head
    def prep(t): return t.replace('\n','\r\n') if crlf else t
    if head.count(prep(a))!=1: raise SystemExit('anchor fail %s %d'%(path,head.count(prep(a))))
    staged=head.replace(prep(a),prep(b))
    sha=run(['git','hash-object','-w','--stdin'],input=staged.encode('utf-8')).decode().strip()
    run(['git','update-index','--cacheinfo','100644,%s,%s'%(sha,path)]); print('blob staged',path)
for p in ['tests/test_evoker_fang_particles.gd','tests/EVOKER_FANG_PARTICLES.md']: run(['git','add','--',p])
print('=== CACHED ==='); print(git('diff','--cached','--stat'))
print('=== WHITESPACE ==='); print(git('diff','--cached','--check') or 'ok')
print('=== REMAINING UNSTAGED (foreign only) ==='); print(git('diff','--numstat'))
