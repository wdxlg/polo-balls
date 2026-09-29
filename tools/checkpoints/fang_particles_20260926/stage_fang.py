import subprocess,re,sys,os
os.chdir(r'E:/godot/polo-balls')
def run(args,input=None):
    r=subprocess.run(args,capture_output=True,input=input)
    if r.returncode!=0: raise SystemExit(' '.join(args)+' FAILED\n'+r.stderr.decode('utf-8','replace')[:900])
    return r.stdout
def git_text(*args):
    return run(['git']+list(args)).decode('utf-8')
FANG='scripts/effects/我的世界/唤魔尖牙.gd'
GROUND='scripts/effects/我的世界/重锤落地冲击.gd'
CTX='MCP_CONTEXT.md'
clean_mine=['scripts/effects/combat_impact_layer.gd','scripts/effects/我的世界/mc_combat_abilities.gd','tests/test_evoker_fang_particles.gd','tests/test_evoker_fang_particles.gd.uid','tests/EVOKER_FANG_PARTICLES.md']
print('HEAD before:',git_text('rev-parse','HEAD').strip())
if git_text('diff','--cached','--stat').strip():
    print('INDEX NOT EMPTY -> abort'); print(git_text('diff','--cached','--stat')); raise SystemExit(3)
for p in clean_mine: run(['git','add','--',p])
def mixed(path,edits,append_from=None):
    head=git_text('show','HEAD:'+path)
    work=open(path,encoding='utf-8').read()
    crlf='\r\n' in head
    def prep(t): return t.replace('\n','\r\n') if crlf else t
    staged=head
    for a,b in edits:
        a2,b2=prep(a),prep(b)
        if staged.count(a2)!=1: raise SystemExit('anchor fail %s count=%d :: %r'%(path,staged.count(a2),a[:70]))
        staged=staged.replace(a2,b2)
    if append_from is not None:
        i=work.find(append_from)
        if i<0: raise SystemExit('tail anchor missing in worktree '+path)
        tail=work[i:]
        if not tail.endswith('\n'): tail+='\n'
        sep='\r\n' if crlf else '\n'
        staged=staged.rstrip('\r\n')+sep+sep+tail
        if crlf: staged=staged.replace('\r\n\r\n'+tail.replace('\n','\r\n'),'\r\n\r\n'+tail) # already normalized above
        if crlf: pass
        staged=staged  # tail inserted raw (LF) -> normalize:
        staged=re.sub(r'(?<!\r)\n','\r\n',staged) if crlf else staged
    blob=staged.encode('utf-8')
    sha=run(['git','hash-object','-w','--stdin'],input=blob).decode().strip()
    run(['git','update-index','--cacheinfo','100644,%s,%s'%(sha,path)])
    print('staged blob for',path,'lines',staged.count('\n'))
mixed(FANG,[
 ('var _caster:WeakRef','const ABILITIES = preload("res://scripts/effects/我的世界/mc_combat_abilities.gd")\nconst RUNTIME = preload("res://scripts/effects/我的世界/mc_explosion.gd")\nvar _emerged:bool = false\nvar _caster:WeakRef'),
 ('\t_age += delta\n','\t_age += delta\n\tif not _emerged and native_animation_progress() >= 0.0:\n\t\t_emerged = true\n\t\t_emit_emergence()\n'),
 ('\t\t_hit = true\n','\t\t_hit = true\n\t\t_emit_bite()\n'),
],append_from='func _emit_emergence() -> void:')
mixed(GROUND,[
 ('@export var block_source_radius_min_scale:float = 0.48','@export var block_source_inner_radius_scale:float = 0.0 # Optional annulus; zero preserves existing callers.\n@export var block_exclusion_radius:float = 0.0 # Reject center births after scatter/map clipping.\n@export var block_source_radius_min_scale:float = 0.48'),
 ('\t\tvar source_world:Vector2 =','\t\tif block_source_inner_radius_scale > 0.0:\n\t\t\tvar inner:float = _radius*block_source_inner_radius_scale\n\t\t\tvar outer:float = maxf(inner,_radius*block_source_radius_max_scale)\n\t\t\tsource_radius = sqrt(lerpf(inner*inner,outer*outer,_rng.randf()))\n\t\tvar source_world:Vector2 ='),
 ('\t\t\tvar outward:Vector2 = start','\t\t\tif block_exclusion_radius > 0.0 and start.length() < block_exclusion_radius: continue\n\t\t\tvar outward:Vector2 = start'),
])
my_bullet='- 唤魔者尖牙出土时复用重锤的小方块碎屑：只取环形外圈采样（`block_source_inner_radius_scale`/`block_exclusion_radius`），上升仅 2–4 像素且不产生中心爆圈/射线；闭合瞬间按原版固定发射 12 颗 CRIT，走 `mc_combat_abilities.gd::critical_burst` 复用世界级批量层，不得新建粒子实现或用粒子代替伤害判定，每轮施法的碎屑批次有限流。回归见 `tests/test_evoker_fang_particles.gd`、`tests/EVOKER_FANG_PARTICLES.md`。\n'
anchor='- Minecraft 范围外圈和蓄力填充盘统一复用'
mixed(CTX,[(anchor,my_bullet+anchor)])
print('=== CACHED STAT ==='); print(git_text('diff','--cached','--stat'))
print('=== CACHED CHECK ==='); print(git_text('diff','--cached','--check') or 'whitespace ok')
print('=== WORKTREE vs INDEX (foreign leftovers) ===')
out=run(['git','diff','--stat','--',FANG,GROUND,CTX]).decode('utf-8','replace')
print(out)
open('tools/checkpoints/fang_particles_20260926/unstaged_after_stage.txt','wb').write(run(['git','diff','--',FANG,GROUND,CTX]))
print('saved unstaged dump',os.path.getsize('tools/checkpoints/fang_particles_20260926/unstaged_after_stage.txt'))
