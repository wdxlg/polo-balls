$path=(Join-Path (Get-Location) "classes/combat_classification_catalog.gd")
$text=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)
if($text.Contains("流浪商人.tscn")){ "ALREADY"; exit }
$nl=if($text.Contains("`r`n")){"`r`n"}else{"`n"}
$anchor=' "res://scenes/characters/我的世界/皓宸.tscn":'
$i=$text.IndexOf($anchor); if($i -lt 0){ "NOANCHOR"; exit 1 }; $j=$text.IndexOf($nl,$i); if($j -lt 0){ "NONL"; exit 1 }; $j=$j+$nl.Length
$add=' "res://scenes/characters/我的世界/流浪商人.tscn": {"entity_kind":"character","attack_modes":["none"],"carriers":["none"],"damage_kinds":[],"review":"summoner_two_leashed_llamas; milk_cleanse_witch_invisibility_wall_phase; no_direct_damage; see docs/WANDERING_TRADER.md","root_script":"res://scripts/characters/我的世界/流浪商人.gd"},'+$nl+' "res://scenes/creatures/流浪商人_羊驼.tscn": {"entity_kind":"subentity","attack_modes":["ranged"],"carriers":[],"damage_kinds":["ordinary_or_contextual"],"review":"killable_leashed_summon; spit_via_projectile; llama_body_speed_damage; see docs/WANDERING_TRADER.md","root_script":"res://scripts/characters/我的世界/wandering_trader/llama.gd"},'+$nl+' "res://scenes/shooter/我的世界/羊驼口水.tscn": {"entity_kind":"projectile","attack_modes":["ranged"],"carriers":["projectile"],"damage_kinds":[],"review":"llama_spit_snowball_contract; see docs/WANDERING_TRADER.md","root_script":"res://scripts/characters/我的世界/wandering_trader/spit.gd"},'+$nl
$text=$text.Substring(0,$j)+$add+$text.Substring($j)
$bom=[IO.File]::ReadAllBytes($path)[0] -eq 0xEF
[IO.File]::WriteAllText($path,$text,(New-Object Text.UTF8Encoding($bom)))
"INSERTED bom=$bom nl=" + ($nl.Length)
Select-String -Path $path -Pattern "流浪商人|羊驼" -Encoding UTF8 | % { $_.LineNumber }
