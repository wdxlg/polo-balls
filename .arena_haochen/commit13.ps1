$paths=@("scripts/characters/我的世界/流浪商人.gd","scripts/characters/我的世界/流浪商人.gd.uid","scripts/characters/我的世界/wandering_trader","scenes/characters/我的世界/流浪商人.tscn","scenes/creatures/流浪商人_羊驼.tscn","scenes/shooter/我的世界/羊驼口水.tscn","Images/characters/我的世界/流浪商人","audio/characters/流浪商人","scripts/training/mc_native_assets/bake_wandering_trader.py","scripts/training/mc_native_assets/sources_trader.json","scripts/training/mc_native_assets/resource_pack_trader","tests/test_wandering_trader.gd","tests/test_wandering_trader.gd.uid","tests/preview_wandering_trader_gpu.gd","tests/WANDERING_TRADER_20260928.md","docs/WANDERING_TRADER.md")
$before=git --no-pager diff --cached --name-only
"STAGED_BEFORE " + ($before -join ",")
git add -- $paths
git commit --only -m "Add Wandering Trader with two leashed trader llamas (task 13)" -m "Leash follow and yank-back ignoring character collision, llama-only speed damage with parallel knockback, llama spit and delayed retaliation, milk cleanse only with negative effects, Witch invisibility, wall phase with safest-exit and leash reconnect. Baked Bedrock frames, vanilla sounds, docs/WANDERING_TRADER.md, tests." -- $paths
"EXIT $LASTEXITCODE"
git --no-pager log --oneline -2
git --no-pager show --stat --oneline HEAD | Select -Last 3
"STAGED_AFTER " + ((git --no-pager diff --cached --name-only) -join ",")
git --no-pager status --short -- translations.csv classes/combat_classification_catalog.gd MCP_CONTEXT.md
