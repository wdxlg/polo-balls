# 流浪商人 test record (2026-09-28, task 13)

Baseline HEAD `8516c4e`. The design is in `docs/WANDERING_TRADER.md`.

## `tests/test_wandering_trader.gd` (real World, Map10x10): 51 checks, 0 failures (3 consecutive runs)

Checks by area:
- **Herd:** exactly 2 llamas; deterministic names `WT_Llama0/1`; Creature summons (Type 3, Master = trader, same team); both leashes connected; 2 world-space leash views; llamas are targetable and killable; baked frames applied.
- **Yank:** a llama past 60 px is pulled back; during the yank it is layer 0 with no character mask; it passes through a same-team character and reaches ≤ 34 px (25.9 measured); the teammate takes no damage; normal collision (2/3) returns after the overlap fallback.
- **Speed damage:**
  - a yanked llama rams an enemy on its path;
  - the ram knocks the enemy along the yank direction (+x);
  - damage is 0 below 130 px/s, exactly 18 at 200, capped at 40;
  - the trader has no speed damage;
  - a direct hit with heading (0,1) moves the target along +y.
- **Spit:** the named shot `WT_Llama1_Spit1` has speed 300 and damage 14; it hits the enemy; spit sound plays; interval is 2.0 s.
- **Retaliation:** none at 0.25 s, one spit at 0.7 s (delay 0.45 s), with the angry sound.
- **Milk:**
  - no drink with only a positive effect;
  - slowness + poison are detected;
  - he drinks, and both are removed (2) while speed stays;
  - no second drink during the cooldown.
- **Invisibility:** after the 0.78 s drink the Witch `invisibility` status is active; drink_potion sound plays.
- **Wall:**
  - entering breaks the leash and disables collision;
  - snap, leash_break and disappeared sounds play;
  - hidden: not visible and untargetable, at the nearest wall tile, stone_break plays, damage is refused, llamas are free;
  - he emerges targetable at the safest slot (93 of best 93 over 32 slots) on body-clear ground;
  - stone_hit and reappeared play; leashes reconnect with leash_place;
  - collision is consistent with invisibility; metas are cleared.
- **Death:** a dead llama loses its leash and does not respawn; manual controls are [attack = potion, skill = wall, middle = milk]; the remaining llama retires with the trader; no leash is left connected.

## `tests/preview_wandering_trader_gpu.gd` (GUI only): screenshots

The screenshots are in `.arena_haochen/t13_shots/`: herd, taut yank, after yank, spit in flight, milk bucket at the mouth, potion at the mouth, invisible, wall entering, hidden, emerging with stone chips, reconnected.
- After the first preview, the rope sag was capped at 7 world px, because a slack rope beside the trader hung below his feet.

## Regressions
| test | result |
|---|---|
| test_all_character_potion_contract | 4259/0 (190 scenes incl. the trader) |
| test_manual_roster_runtime_audit | 233 loaded / 0 failed; the trader is listed with 3 manual actions; the llama is listed as a creature |
| test_battle_lifecycle | 83/0 |
| test_haochen_copy_friendly_sweep | 286 copies incl. the trader (with its llamas): 0 offenders, 0 size issues, 0 ally hits |
| test_combat_classification | 3 new scenes registered in `classes/combat_classification_catalog.gd` (untracked shared file, left uncommitted). The only remaining failure is someone else's `jjk_domain.gd` attack mode (pre-existing). |

## Notes
- Every map's TileMapLayer has `collision_enabled = false` (World builds its own bounce walls), so wall tiles are identified by their tile-data collision polygons. With no wall tiles, the arena edge is used as the fallback.
- The direct-knockback check is measured away from the herd with the llamas paused: next to the moving llamas, crowd separation once added its own displacement.
- `retire()` no longer puts a freed trader into a typed loop variable; this error was found by the potion contract sweep.
