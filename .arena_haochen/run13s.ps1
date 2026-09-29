$e="E:/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe"
"" | Set-Content .arena_haochen/t13s.txt -Encoding UTF8
function RunT($n,$log){ $p=Start-Process -FilePath $e -ArgumentList @("--path",".","--log-file",$log,"--script","res://tests/$n.gd") -Wait -PassThru -NoNewWindow; $sum=(Get-Content $log -Encoding UTF8 | Select-String -Pattern "checks=|RESULT|passed|failed" | Select -Last 3 | % { $_.Line }) -join " | "; $f=(Get-Content $log -Encoding UTF8 | Select-String -Pattern "FAIL|流浪商人|wandering_trader" | Where-Object { $_.Line -notmatch "PASS" } | Select -First 6 | % { $_.Line }) -join " || "; "$n exit=$($p.ExitCode) :: $sum :: $f" | Add-Content .arena_haochen/t13s.txt -Encoding UTF8 }
RunT "test_wandering_trader" ".arena_haochen/t13s_wt.log"
RunT "test_all_character_potion_contract" ".arena_haochen/t13s_potion.log"
RunT "test_combat_classification" ".arena_haochen/t13s_class.log"
$d=(Join-Path (Get-Location) ".arena_haochen/t13_shots2"); New-Item -ItemType Directory -Force $d | Out-Null; $env:WANDERING_TRADER_EVIDENCE_DIR=$d
RunT "preview_wandering_trader_gpu" ".arena_haochen/t13s_gpu.log"
"ALLDONE" | Add-Content .arena_haochen/t13s.txt -Encoding UTF8
