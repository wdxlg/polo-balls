$e="E:/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe"
"" | Set-Content .arena_haochen/t13r.txt -Encoding UTF8
function RunT($n,$log){ $p=Start-Process -FilePath $e -ArgumentList @("--path",".","--log-file",$log,"--script","res://tests/$n.gd") -Wait -PassThru -NoNewWindow; $sum=(Get-Content $log -Encoding UTF8 | Select-String -Pattern "checks=|RESULT|passed|failed" | Select -Last 3 | % { $_.Line }) -join " | "; $f=(Get-Content $log -Encoding UTF8 | Select-String -Pattern "FAIL|流浪商人|wandering_trader" | Where-Object { $_.Line -notmatch "PASS" } | Select -First 6 | % { $_.Line }) -join " || "; "$n exit=$($p.ExitCode) :: $sum :: $f" | Add-Content .arena_haochen/t13r.txt -Encoding UTF8 }
RunT "test_wandering_trader" ".arena_haochen/t13r_wt.log"
RunT "test_all_character_potion_contract" ".arena_haochen/t13r_potion.log"
RunT "test_manual_roster_runtime_audit" ".arena_haochen/t13r_roster.log"
RunT "test_combat_classification" ".arena_haochen/t13r_class.log"
RunT "test_haochen_copy_friendly_sweep" ".arena_haochen/t13r_sweep.log"
"ALLDONE" | Add-Content .arena_haochen/t13r.txt -Encoding UTF8
