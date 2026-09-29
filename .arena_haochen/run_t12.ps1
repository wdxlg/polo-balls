$e="E:/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe"
$list=@(@("test_duel_top_hud",1),@("test_vs_screen_title",0),@("test_day_night_cycle",0),@("test_day_night_visual",1))
"" | Set-Content .arena_haochen/t12_suite.txt -Encoding UTF8
foreach($t in $list){
 $n=$t[0]; $log=".arena_haochen/t12s_$n.log"
 if($t[1] -eq 1){$a=@("--path",".","--log-file",$log,"--script","res://tests/$n.gd")}else{$a=@("--headless","--fixed-fps","60","--path",".","--log-file",$log,"--script","res://tests/$n.gd")}
 $p=Start-Process -FilePath $e -ArgumentList $a -Wait -PassThru -NoNewWindow
 $sum=(Get-Content $log -Encoding UTF8 | Select-String -Pattern "checks=|passed|PASS" | Select-Object -Last 3 | ForEach-Object { $_.Line }) -join " | "
 $fails=(Get-Content $log -Encoding UTF8 | Select-String -Pattern "FAIL|SCRIPT ERROR|Parse Error" | Select-Object -First 8 | ForEach-Object { $_.Line }) -join " || "
 "$n exit=$($p.ExitCode) :: $sum :: $fails" | Add-Content .arena_haochen/t12_suite.txt -Encoding UTF8
}
"ALLDONE" | Add-Content .arena_haochen/t12_suite.txt -Encoding UTF8
