Copy-Item MCP_CONTEXT.md .arena_haochen/backups/task13/MCP_CONTEXT.md.before -Force
$path=(Join-Path (Get-Location) "MCP_CONTEXT.md")
$bytes=[IO.File]::ReadAllBytes($path); $bom=($bytes[0] -eq 0xEF)
$text=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)
if($text.Contains("流浪商人（2026-09-28）")){ "ALREADY"; exit }
$nl=if($text.Contains("`r`n")){"`r`n"}else{"`n"}
$anchor="- 皓宸（2026-09-28）"
$i=$text.IndexOf($anchor); if($i -lt 0){ "NOANCHOR"; exit 1 }
$j=$text.IndexOf($nl,$i); if($j -lt 0){ "NONL"; exit 1 }; $j=$j+$nl.Length
$line="- 流浪商人（2026-09-28）：自带两只缰绳羊驼（可被击杀、不复活、不计胜负，商人死亡随之退场）；超出缰绳距离时羊驼被拉回并无视人物碰撞（layer 0/mask 1），仅羊驼身体按速度造成伤害并沿其运动方向击退；羊驼口水（间隔2.0s、弹速300）与受击0.45s后反击口水；商人仅在有负面效果时喝牛奶（与铜剑同一清除，冷却20s），喝女巫同款隐身药水，入墙技能（冷却11s：缰绳断开→隐藏不可选中→从最安全的墙位出来→缰绳重连）。地图TileMapLayer的collision_enabled均为关，墙位按瓦片碰撞多边形识别。规则与数值见 ``docs/WANDERING_TRADER.md``，测试见 ``tests/WANDERING_TRADER_20260928.md``；翻译行、分类目录三条场景登记属共享文件未入库。"
$text=$text.Substring(0,$j)+$line+$nl+$text.Substring($j)
[IO.File]::WriteAllText($path,$text,(New-Object Text.UTF8Encoding($bom)))
"INSERTED bom=$bom"
Select-String -Path $path -Pattern "流浪商人（" -Encoding UTF8 | % { $_.LineNumber }
