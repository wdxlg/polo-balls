$e="E:/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe"
"" | Set-Content .arena_haochen/t13.txt -Encoding UTF8
$p=Start-Process -FilePath $e -ArgumentList @("--headless","--path",".","--log-file",".arena_haochen/t13_import.log","--import") -Wait -PassThru -NoNewWindow
"import exit=$($p.ExitCode)" | Add-Content .arena_haochen/t13.txt -Encoding UTF8
function RunT($n,$log){ $p=Start-Process -FilePath $e -ArgumentList @("--path",".","--log-file",$log,"--script","res://tests/$n.gd") -Wait -PassThru -NoNewWindow; $sum=(Get-Content $log -Encoding UTF8 | Select-String -Pattern "checks=" | % { $_.Line }) -join " | "; "$log exit=$($p.ExitCode) :: $sum" | Add-Content .arena_haochen/t13.txt -Encoding UTF8 }
RunT "test_wandering_trader" ".arena_haochen/t13_wt1.log"
"ALLDONE" | Add-Content .arena_haochen/t13.txt -Encoding UTF8
