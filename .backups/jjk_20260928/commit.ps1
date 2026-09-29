[Console]::OutputEncoding=[Text.Encoding]::UTF8
$d="scripts/characters/动漫/咒术回战"
$files=@("docs/JJK_CHARACTERS.md","scenes/characters/动漫/五条悟.tscn","scenes/characters/动漫/宿傩.tscn","scenes/characters/动漫/嵌合暗兽.tscn","scenes/characters/动漫/魔虚罗.tscn",
"$d/agito.gd","$d/gojo.gd","$d/jjk_base.gd","$d/jjk_domain.gd","$d/jjk_fx.gd","$d/jjk_projectile.gd","$d/jjk_vfx.gd","$d/mahoraga.gd","$d/sukuna.gd",
"$d/jjk_cutin.gd","$d/jjk_cutin.gd.uid","$d/jjk_distort.gd","$d/jjk_distort.gd.uid","$d/jjk_distort.gdshader","$d/jjk_distort.gdshader.uid","$d/jjk_screen.gdshader","$d/jjk_screen.gdshader.uid","$d/jjk_screenfx.gd","$d/jjk_screenfx.gd.uid","$d/jjk_vfx.gd.uid","$d/jjk_vfx_atlas.gd","$d/jjk_vfx_atlas.gd.uid",
"Images/characters/动漫/咒术回战/vfx","sources/jjk/vfx/SOURCES.json","tests/test_jjk.gd","tests/test_jjk_fx_gallery.gd","tests/test_jjk_size_compare.gd","tests/test_jjk_size_compare.gd.uid","tests/test_jjk.gd.uid","tests/test_jjk_domain_gallery.gd.uid","tests/test_jjk_fx_gallery.gd.uid","tests/test_jjk_gpu.gd.uid","tools/build_jjk_vfx.py")
foreach ($f in $files) { if (-not (Test-Path $f)) { "MISSING $f" } }
git add -- $files
if ($LASTEXITCODE -ne 0) { "ADD FAILED"; exit 1 }
git -c core.quotepath=false diff --cached --stat | Select-Object -Last 3
git -c core.quotepath=false diff --cached --name-only | Select-String "菜月昴|死亡回归"
git commit -q -m "JJK: VFX 2.0 (CC0 sprite sheets, distortion/screen shaders, cut-ins, shake/hitstop), normal-size characters, roster-level damage/HP"
git log --oneline -4

