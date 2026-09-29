$paths=@("scripts/characters/我的世界/流浪商人.gd","scripts/characters/我的世界/流浪商人.gd.uid","scripts/characters/我的世界/wandering_trader","scenes/characters/我的世界/流浪商人.tscn","scenes/creatures/流浪商人_羊驼.tscn","scenes/shooter/我的世界/羊驼口水.tscn","Images/characters/我的世界/流浪商人","audio/characters/流浪商人","scripts/training/mc_native_assets/bake_wandering_trader.py","scripts/training/mc_native_assets/sources_trader.json","scripts/training/mc_native_assets/resource_pack_trader","tests/test_wandering_trader.gd","tests/test_wandering_trader.gd.uid","tests/preview_wandering_trader_gpu.gd","tests/preview_wandering_trader_gpu.gd.uid","tests/WANDERING_TRADER_20260928.md","docs/WANDERING_TRADER.md")
$lines=git --no-pager status --short --untracked-files=all -- $paths
$lines | Set-Content .arena_haochen/t13_commit_status.txt -Encoding UTF8
"TOTAL " + $lines.Count
$lines | % { $_.Substring(0,2) } | Group-Object | % { "CODE [" + $_.Name + "] " + $_.Count }
$lines | ? { $_ -notmatch "\.(png|ogg|import)$" } | % { $_ }
"MC line ok: " + ((Get-Content MCP_CONTEXT.md -Encoding UTF8)[5].Contains('`docs/WANDERING_TRADER.md`'))
git --no-pager status --short -- scripts/training/mc_native_assets | ? { $_ -notmatch "trader" } | Select -First 5
