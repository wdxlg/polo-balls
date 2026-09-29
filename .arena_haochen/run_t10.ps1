$e="E:/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe"
$env:HAOCHEN_SWEEP_ONLY="";$env:HAOCHEN_SWEEP_TRACE="";$env:HAOCHEN_SWEEP_MODE=""
$list=@(@("test_haochen",0),@("test_haochen_reuse",0),@("test_haochen_network",0),@("test_haochen_task8",0),@("test_haochen_task10",0),@("test_manual_control_roster_extensions",0),@("test_mc_bat",0),@("test_slime_family_victory",0),@("test_void_projectile_contacts",0),@("test_haochen_task9",1),@("test_haochen_real_battle_gpu",1),@("test_haochen_visual_audio",1),@("test_haochen_face_link_gpu",1))
"" | Set-Content .arena_haochen/t10_suite.txt -Encoding UTF8
foreach($t in $list){
 $n=$t[0]; $log=".arena_haochen/t10s_$n.log"
 if($t[1] -eq 1){$a=@("--path",".","--log-file",$log,"--script","res://tests/$n.gd")}else{$a=@("--headless","--fixed-fps","60","--path",".","--log-file",$log,"--script","res://tests/$n.gd")}
 $p=Start-Process -FilePath $e -ArgumentList $a -Wait -PassThru -NoNewWindow
 $sum=(Get-Content $log -Encoding UTF8 | Select-String -Pattern "checks=|passed|failed" | ForEach-Object { $_.Line }) -join " | "
 $fails=(Get-Content $log -Encoding UTF8 | Select-String -Pattern "FAIL" | Select-Object -First 5 | ForEach-Object { $_.Line }) -join " || "
 "$n exit=$($p.ExitCode) :: $sum :: $fails" | Add-Content .arena_haochen/t10_suite.txt -Encoding UTF8
}
"ALLDONE" | Add-Content .arena_haochen/t10_suite.txt -Encoding UTF8
