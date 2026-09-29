$e="E:/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe"
"" | Set-Content .arena_haochen/t13g.txt -Encoding UTF8
$d=(Join-Path (Get-Location) ".arena_haochen/t13_shots")
New-Item -ItemType Directory -Force $d | Out-Null
$env:WANDERING_TRADER_EVIDENCE_DIR=$d
$p=Start-Process -FilePath $e -ArgumentList @("--path",".","--log-file",".arena_haochen/t13_gpu.log","--script","res://tests/preview_wandering_trader_gpu.gd") -Wait -PassThru -NoNewWindow
$sum=(Get-Content .arena_haochen/t13_gpu.log -Encoding UTF8 | Select-String -Pattern "checks=|FAIL|SCRIPT ERROR" | % { $_.Line }) -join " | "
"gpu exit=$($p.ExitCode) :: $sum" | Add-Content .arena_haochen/t13g.txt -Encoding UTF8
"ALLDONE" | Add-Content .arena_haochen/t13g.txt -Encoding UTF8
