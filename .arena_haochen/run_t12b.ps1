$e="E:/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe"
"" | Set-Content .arena_haochen/t12b.txt -Encoding UTF8
$p=Start-Process -FilePath $e -ArgumentList @("--path",".","--log-file",".arena_haochen/t12s_test_duel_top_hud.log","--script","res://tests/test_duel_top_hud.gd") -Wait -PassThru -NoNewWindow
"duel exit=$($p.ExitCode)" | Add-Content .arena_haochen/t12b.txt -Encoding UTF8
Copy-Item scripts/ui/duel_top_hud.gd .arena_haochen/t12_new_hud.gd -Force
Copy-Item .arena_haochen/backups/task12/duel_top_hud.gd scripts/ui/duel_top_hud.gd -Force
$p=Start-Process -FilePath $e -ArgumentList @("--path",".","--log-file",".arena_haochen/t12s_dnv_base.log","--script","res://tests/test_day_night_visual.gd") -Wait -PassThru -NoNewWindow
Copy-Item .arena_haochen/t12_new_hud.gd scripts/ui/duel_top_hud.gd -Force
"dnv_base exit=$($p.ExitCode)" | Add-Content .arena_haochen/t12b.txt -Encoding UTF8
$p=Start-Process -FilePath $e -ArgumentList @("--path",".","--log-file",".arena_haochen/t12s_dnv_new2.log","--script","res://tests/test_day_night_visual.gd") -Wait -PassThru -NoNewWindow
"dnv_new2 exit=$($p.ExitCode)" | Add-Content .arena_haochen/t12b.txt -Encoding UTF8
"ALLDONE" | Add-Content .arena_haochen/t12b.txt -Encoding UTF8
