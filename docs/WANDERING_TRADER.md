# 流浪商人 (Wandering Trader) + 两只羊驼

Added 2026-09-28 (task 13). User request (verbatim):

> 加一个流浪商人角色。自带两个羊驼。有个缰绳连着商人和羊驼。羊驼会跟随流浪商人。商人和羊驼隔得远了会把羊驼拉过来。拉过来的时候无视人物碰撞。可以根据速度对敌人造成伤害和击退（向平行方向击退）。羊驼还会射出口水攻击。攻速中等。子弹速度中等偏快。羊驼受击延迟一会还会射口水。然后商人会喝牛奶，清除一切负面效果（就和铜剑一样）。只有有负面效果的时候才会喝。有长冷却。还会喝隐身药水，和女巫的一样。还有一个技能冷却中等。可以进入地图的墙然后消失。缰绳会断开。过一会会从一个尽量安全的地方出来（从墙里出来）。缰绳会在他出来的时候连上。

User decisions:
- Llamas: **killable, no respawn** (summons with their own HP; the leash goes away when one dies; they never count for victory).
- Speed damage: **llama body only**, knockback along the llama's own motion. Neither the rope nor the trader deals speed damage.
- While hidden in a wall: **llamas roam and fight freely**.
- Numbers: default (I picked them from existing MC characters, listed below).

## Files

| Path | Role |
|---|---|
| `scenes/characters/我的世界/流浪商人.tscn` | trader (ball.tscn instance) |
| `scripts/characters/我的世界/流浪商人.gd` | trader AI, milk / potion / wall phase, leash views, manual controls |
| `scenes/creatures/流浪商人_羊驼.tscn` | trader llama (Type Creature) |
| `scripts/characters/我的世界/wandering_trader/llama.gd` | follow, yank, speed damage, spit, retaliation, death |
| `scenes/shooter/我的世界/羊驼口水.tscn` + `wandering_trader/spit.gd` | spit projectile (snowball contract) |
| `wandering_trader/leash.gd` | rope drawing: sagging catenary-like curve, taut line, snap/connect animation |
| `wandering_trader/wall_phase.gd` | wall-slot geometry, nearest / safest slot |
| `wandering_trader/visual.gd` | baked frame driver, held item, block-chip particles |
| `wandering_trader/audio.gd` | vanilla sound events |
| `Images/characters/我的世界/流浪商人/frames/` | baked Bedrock frames (trader, llama_creamy, llama_brown, llama_spit) |
| `Images/characters/我的世界/流浪商人/items/milk_bucket.png` | held milk bucket icon |
| `audio/characters/流浪商人/` + `SOURCE.json` | 55 vanilla oggs |
| `scripts/training/mc_native_assets/bake_wandering_trader.py`, `sources_trader.json`, `resource_pack_trader/` | reproducible bake from Mojang/bedrock-samples @ `736072450c26a7c67f07b1661f29d9a5ebaa14b1` |
| `tests/test_wandering_trader.gd` | functional test in a real World |

## Rules

### Herd and leash
- On `_ready` (authority, deferred) the trader spawns `llama_count = 2` llamas named `<trader>_Llama<i>`, `Master = trader`, same Team. Slot 0 is creamy, slot 1 brown (derived from the name, so every peer agrees).
- The trader, and the llamas among themselves, have mutual collision exceptions, so the herd never jams on itself.
- Leash views live in world space under the battle scene: they are not inherited from the trader's transform, and they stay visible to play the snap while he is hidden. Every peer draws them from the trader hand (`hand_point`) to the llama neck (`wt_neck_point`). Rope colours are vanilla lead brown (127,102,76) / (89,71,53).
- Follow: within `leash_slack = 42` the llama idles next to the trader, drifts toward targets out of spit range, and walks back once it is past 75 % of the slack.
- **Yank**: when the distance exceeds `leash_pull_start = 60`, the llama is pulled at 170–340 px/s until it is within `leash_pull_end = 28`. During the yank it uses layer 0 / mask 1 (walls only), i.e. it **ignores every character body**. Normal collision returns only where the body does not overlap a character (or after 1.5 s). If a map wall blocks the yank for 1 s the leash drags it through (mask 0).

### Speed damage (llama body only)
- Every llama move sweeps a capsule along its actual path (this frame's displacement) against enemy hurtboxes.
- Speed ≥ 130 px/s gives damage `speed × 0.09` (130 → 11.7, 200 → 18, cap 40), passed through `effective_outgoing_damage`. Each target is hit at most once per 0.45 s.
- Knockback is `apply_knockback(heading, clamp(speed×0.1, 6, 38), max(speed×1.15, 200))`, where heading is the llama's own movement direction (parallel knockback).
- In practice this happens when the leash yanks a llama through enemies; normal walking (≤ 62 px/s) never deals damage.

### Spit
- Range 135, interval 2.0 s ± 0.35 (medium), projectile speed 300 (medium-fast; snowball is 260). Damage = the llama's `attack_damage()` (Damage 14). Knockback 6. Lifetime 2.2 s.
- The llama leads the target slightly. Shots need line of sight; walls expire them.
- Hit test: a swept circle each frame through the common hitbox path, so shields, blocks and boats are respected.
- **Retaliation**: after taking real HP damage, the llama spits at the attacker after 0.45 s, or at the nearest enemy if the attacker cannot be resolved. Minimum 0.9 s between retaliations. Plays `entity.llama.angry`.

### Milk (long cooldown)
- The trader checks every 0.2 s whether a **negative** effect exists, using a read-only mirror of `classes/status_cleansing.gd`'s candidates (status nodes, registered effects, legacy Buffs with `is_negative_for`).
- If a negative effect exists and the 20 s cooldown is ready, he drinks for 1.1 s (movement ×0.35), then calls `cleanse_negative_effects()`. This is the same one-shot cleanse the copper sword uses: positive effects stay.
- Sound: `entity.wandering_trader.drink_milk`.

### Invisibility potion
- He drinks for 0.78 s (the Witch's drink time), then calls `女巫药水效果.apply_effect(self,"invisibility",self)`: exactly the Witch's effect (6 s, no AI locking, no character-body collision, faded sprite, contact chip damage).
- AI trigger: an enemy within 70, or hurt within the last 1 s. Cooldown 16 s, first use after 5 s. Sound: `entity.wandering_trader.drink_potion`.

### Wall (入墙, medium cooldown 11 s, first use after 7 s)
- **Wall slots**: every map tile with a physics-layer-1 collision polygon that touches a walkable tile. PortalMap islands use their own layers. Maps without tiles fall back to the arena edges.
- **AI trigger**: an enemy within 60, or hurt within 0.8 s while HP < 60 %.

The phase runs in four steps:
1. **Entering**: he slides into the nearest wall tile (0.25–0.85 s), with collision off and no AI locking. The leashes snap (`entity.leash_knot.break` + `entity.wandering_trader.disappeared`).
2. **Hidden** (2.6 s): hidden on all peers and untargetable. Damage, hit contacts and knockback are ignored. Plays `block.stone.break` with stone chips. The llamas roam, chase and spit on their own.
3. **Emerging**: the exit is chosen by `WALL.safest_slot`. Slots are ranked by the distance from their floor tile to the nearest enemy (plus ≤ 6 px seeded jitter), and the first slot whose floor can hold his whole body wins (stepping out along the wall normal up to 22 px). He appears inside that wall tile and steps out over 0.4 s (`block.stone.hit` + `reappeared` + chips).
4. **Finish**: collision and metas are restored (bit 2 is re-added if invisibility expired meanwhile) and the leashes reconnect (`entity.leash_knot.place`).

If the battle stops mid-phase, `finish_wall_phase_now()` pops him out at once.

### Death and lifecycle
- Llamas have HP 145. `retire()` removes them from the Ball group, snaps their leash (`wt_on_llama_lost`) and frees them. **No respawn.** As Type Creature they are not battle characters, so they never count for victory.
- When the trader dies, `owner_lost()` retires the remaining llamas (vanilla trader llamas despawn with him). World resets free them with every Ball.

### Manual control
- Left click: invisibility potion.
- Right click: enter a wall.
- Middle click: milk (only with a negative effect).

### Multiplayer
- Llama spawns go through the auto-spawnable scene path with deterministic names. Spit uses the snowball pattern: authority spawns it locally and via rpc, with deterministic names.
- Sounds are rpc'd with the chosen variant.
- The drink visual, wall hide/show and leash state go by reliable rpc. The leash is drawn locally on every peer.

## Numbers

| | value | reference |
|---|---|---|
| Trader HP / Speed | 520 / 80 | Witch 500 / 76 |
| Llama HP / follow speed | 145 / 62 | dog 75, vex |
| Spit damage / speed / interval | 14 / 300 / 2.0 s | snowball 6 / 260 |
| Speed damage | from 130 px/s, ×0.09, cap 40 | |
| Milk cooldown / drink | 20 s / 1.1 s | |
| Invisibility cooldown / first / drink | 16 s / 5 s / 0.78 s | Witch drink 0.78 s |
| Wall cooldown / first / hidden / emerge | 11 s / 7 s / 2.6 s / 0.4 s | |
| Leash slack / pull start / pull end | 42 / 60 / 28 world px | |

## Art and sound sources

- Bedrock `resource_pack` @ `736072450c26a7c67f07b1661f29d9a5ebaa14b1`: `entity/wandering_trader.entity.json` (geometry.villager_v2, scale 0.9375, `villager.general/move/raise_arms`), `entity/trader_llama` (geometry.llama.v1.8, creamy/brown + `trader_llama_decor`), `llama_spit` (geometry.llamaspit).
- The baker renders these at 4.265625 px/unit. Frames face LEFT.
- Documented deviations: the llama body is rotated 90° about X as in `llama.setup`; the trader hat brim is skipped (a flat plane viewed edge-on); the decor uses +0.5 inflate; the spit uses a 96×96 canvas at ×2 scale.
- The drink clip uses the vanilla raised-arm pose.
- Sounds: Java Edition equivalents of the Bedrock `.fsb` events (see `audio/characters/流浪商人/SOURCE.json`).
