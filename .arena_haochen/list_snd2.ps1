$root = "C:/Users/q2283/AppData/Roaming/.minecraft/assets"
$idx = Get-Content -Raw "$root/indexes/1.21.json" | ConvertFrom-Json
$idx.objects.PSObject.Properties | Where-Object { $_.Name -match 'sounds/mob/wandering|sounds/mob/villager/' } | ForEach-Object { "$($_.Name) $($_.Value.hash) $($_.Value.size)" }
$h = $idx.objects.'minecraft/sounds.json'.hash
$snd = Get-Content -Raw -Encoding UTF8 "$root/objects/$($h.Substring(0,2))/$h" | ConvertFrom-Json
$snd.PSObject.Properties | Where-Object { $_.Name -match '^entity\.(wandering_trader|llama|leash_knot)\.|^block\.stone\.(break|hit|step)$|^entity\.generic\.drink$' } | ForEach-Object { $s = $_.Value.sounds | ForEach-Object { if ($_ -is [string]) { $_ } else { "$($_.name)(v=$($_.volume),p=$($_.pitch),w=$($_.weight))" } }; "EV $($_.Name) :: $($s -join ', ')" }
