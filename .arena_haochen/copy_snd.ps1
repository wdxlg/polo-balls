$ErrorActionPreference = "Stop"
$root = "C:/Users/q2283/AppData/Roaming/.minecraft/assets"
$idx = Get-Content -Raw "$root/indexes/1.21.json" | ConvertFrom-Json
$dest = "audio/characters/流浪商人"
New-Item -ItemType Directory -Force $dest | Out-Null
$map = [ordered]@{}
function Add([string]$prefix,[string]$src,[string]$event,[int[]]$nums) { foreach ($n in $nums) { $s = if ($n -gt 0) { "$src$n" } else { $src }; $f = if ($n -gt 0) { "$prefix$n.ogg" } else { "$prefix.ogg" }; $script:map[$f] = @($s,$event) } }
Add "trader_idle" "mob/wandering_trader/idle" "entity.wandering_trader.ambient" (1..5)
Add "trader_hurt" "mob/wandering_trader/hurt" "entity.wandering_trader.hurt" (1..4)
Add "trader_death" "mob/wandering_trader/death" "entity.wandering_trader.death" @(0)
Add "trader_disappeared" "mob/wandering_trader/disappeared" "entity.wandering_trader.disappeared" (1..2)
Add "trader_reappeared" "mob/wandering_trader/reappeared" "entity.wandering_trader.reappeared" (1..2)
Add "trader_drink_milk" "mob/wandering_trader/drink_milk" "entity.wandering_trader.drink_milk" (1..5)
Add "trader_drink_potion" "mob/wandering_trader/drink_potion" "entity.wandering_trader.drink_potion" @(0)
Add "generic_drink" "random/drink" "entity.wandering_trader.drink_potion (second variant) / entity.generic.drink" @(0)
Add "llama_idle" "mob/llama/idle" "entity.llama.ambient" (1..5)
Add "llama_hurt" "mob/llama/hurt" "entity.llama.hurt" (1..3)
Add "llama_death" "mob/llama/death" "entity.llama.death" (1..2)
Add "llama_spit" "mob/llama/spit" "entity.llama.spit" (1..2)
Add "llama_step" "mob/llama/step" "entity.llama.step" (1..5)
Add "llama_angry" "mob/llama/angry" "entity.llama.angry" (1..1)
Add "leash_break" "entity/leashknot/break" "entity.leash_knot.break" (1..3)
Add "leash_place" "entity/leashknot/place" "entity.leash_knot.place" (1..3)
Add "stone_break" "dig/stone" "block.stone.break" (1..4)
Add "stone_hit" "step/stone" "block.stone.hit" (1..6)
$entries = @()
foreach ($k in $map.Keys) {
  $src = $map[$k][0]; $ev = $map[$k][1]
  $o = $idx.objects."minecraft/sounds/$src.ogg"
  if ($null -eq $o) { throw "missing $src" }
  $h = $o.hash
  Copy-Item "$root/objects/$($h.Substring(0,2))/$h" "$dest/$k" -Force
  $entries += [ordered]@{ new_asset = $k; original_path = "minecraft/sounds/$src.ogg"; sha1 = $h; event = $ev }
}
$doc = [ordered]@{
  source = "Locally installed Minecraft Java asset index 1.21.json (used by 1.21.1) and its hashed original objects under .minecraft/assets/objects; bytes copied unchanged"
  rights = "Minecraft assets are copyright Mojang Studios/Microsoft. Use is subject to the Minecraft EULA; no general redistribution permission is claimed."
  used_by = "scripts/characters/我的世界/wandering_trader/audio.gd (流浪商人 / 羊驼 / 缰绳 / 墙体进出)"
  files = $entries
}
[IO.File]::WriteAllText((Resolve-Path $dest).Path + "/SOURCE.json", ($doc | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding($false)))
"COPIED $($entries.Count)"
