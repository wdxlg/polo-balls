$e="E:/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe"
"" | Set-Content .arena_haochen/t12c.txt -Encoding UTF8
function RunT($n,$log){ $p=Start-Process -FilePath $e -ArgumentList @("--path",".","--log-file",$log,"--script","res://tests/$n.gd") -Wait -PassThru -NoNewWindow; $sum=(Get-Content $log -Encoding UTF8 | Select-String -Pattern "checks=" | % { $_.Line }) -join " | "; $f=(Get-Content $log -Encoding UTF8 | Select-String -Pattern "FAIL" | Select -First 3 | % { $_.Line }) -join " || "; "$log exit=$($p.ExitCode) :: $sum :: $f" | Add-Content .arena_haochen/t12c.txt -Encoding UTF8 }
RunT "test_duel_top_hud" ".arena_haochen/t12c_duel1.log"
RunT "test_duel_top_hud" ".arena_haochen/t12c_duel2.log"
RunT "test_day_night_visual" ".arena_haochen/t12c_dnv1.log"
RunT "test_day_night_visual" ".arena_haochen/t12c_dnv2.log"
Copy-Item scripts/ui/duel_top_hud.gd .arena_haochen/t12_new_hud.gd -Force
Copy-Item .arena_haochen/backups/task12/duel_top_hud.gd scripts/ui/duel_top_hud.gd -Force
RunT "test_day_night_visual" ".arena_haochen/t12c_dnvbase.log"
Copy-Item .arena_haochen/t12_new_hud.gd scripts/ui/duel_top_hud.gd -Force
"ALLDONE" | Add-Content .arena_haochen/t12c.txt -Encoding UTF8
