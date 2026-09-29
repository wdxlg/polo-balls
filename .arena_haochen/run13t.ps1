$e="E:/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe"
"" | Set-Content .arena_haochen/t13t.txt -Encoding UTF8
function RunT($n,$log){ $p=Start-Process -FilePath $e -ArgumentList @("--path",".","--log-file",$log,"--script","res://tests/$n.gd") -Wait -PassThru -NoNewWindow; $sum=(Get-Content $log -Encoding UTF8 | Select-String -Pattern "checks=|RESULT" | Select -Last 2 | % { $_.Line }) -join " | "; $f=(Get-Content $log -Encoding UTF8 | Select-String -Pattern "FAIL|wandering_trader" | Where-Object { $_.Line -notmatch "PASS" } | Select -First 6 | % { $_.Line }) -join " || "; "$n exit=$($p.ExitCode) :: $sum :: $f" | Add-Content .arena_haochen/t13t.txt -Encoding UTF8 }
RunT "test_wandering_trader" ".arena_haochen/t13t_wt1.log"
RunT "test_wandering_trader" ".arena_haochen/t13t_wt2.log"
RunT "test_wandering_trader" ".arena_haochen/t13t_wt3.log"
RunT "test_battle_lifecycle" ".arena_haochen/t13t_life.log"
"ALLDONE" | Add-Content .arena_haochen/t13t.txt -Encoding UTF8
