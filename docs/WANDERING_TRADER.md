# 流浪商人 (Wandering Trader) + 两只羊驼

Added 2026-09-28 (task 13). User request (verbatim):

> 加一个流浪商人角色。自带两个羊驼。有个缰绳连着商人和羊驼。羊驼会跟随流浪商人。商人和羊驼隔得远了会把羊驼拉过来。拉过来的时候无视人物碰撞。可以根据速度对敌人造成伤害和击退（向平行方向击退）。羊驼还会射出口水攻击。攻速中等。子弹速度中等偏快。羊驼受击延迟一会还会射口水。然后商人会喝牛奶，清除一切负面效果（就和铜剑一样）。只有有负面效果的时候才会喝。有长冷却。还会喝隐身药水，和女巫的一样。还有一个技能冷却中等。可以进入地图的墙然后消失。缰绳会断开。过一会会从一个尽量安全的地方出来（从墙里出来）。缰绳会在他出来的时候连上。

User decisions:
- Llamas: **killable** (summons with their own HP; the leash goes away when one dies; they never count for victory). A dead llama's slot gets a 20 s return cooldown; once it is over, the next wall exit brings one llama back out of the wall with him, leashed.
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
| `wandering_trader/wall_phase.gd` | wall-slot geometry (wall / floor / face / normal), nearest / safest slot |
| `wandering_trader/wall_clip.gd` | clips the body on the wall surface while walking in / out |
| `wandering_trader/spit_smoke.gd` | vanilla spit smoke puffs released with each shot |
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
- **Vanilla look** (fixed 2026-09-28 after user feedback "羊驼口水和原游戏不一样"):
  - The model (geometry.llamaspit, baked facing left) is turned to the flight direction every frame, like `animation.llama_spit.setup`.
  - The launch releases 7 spit smoke puffs (`wandering_trader/spit_smoke.gd`), as in Java `LlamaSpit.recreateFromPacket` + `SpitParticle`/`ExplodeParticle`. Puff *i* flies at shot velocity × (0.4 + 0.1·i) with a ±0.05/1.5 speed jitter and 0.9 friction per tick. Shade is 0.7–1.0 grey, size is 0.1·(r·r·6 + 1) half-width in blocks (1 block ≈ 16 px), lifetime is 16/(r·0.8 + 0.2) + 2 ticks, and frames play `generic_7 → generic_0` (the same flipbook as Bedrock `particles/llama_spit.json`). The puffs are purely visual, generated on every peer, and have no gravity on the top-down field.
  - Impacts spawn nothing extra (vanilla only discards the entity). The old white-cyan block-chip splash was removed.
  - **Hit sound** (MCP_CONTEXT §1): every real HP loss from spit or speed damage plays `entity.player.hurt` (≤50) / `entity.player.attack.crit` (>50) at the victim with `hit_audio_gain.damage_gain` (0 dB base). The events come from the shared `new5/audio.gd` table (`mc_native_audio.gd` has no hit events and silently plays nothing). The llama plays it (`wt_hit_sound`, reliable rpc to peers) because the spit frees itself on hit; the player is parented to the current scene.
- **Retaliation**: after taking real HP damage, the llama spits at the attacker after 0.45 s, or at the nearest enemy if the attacker cannot be resolved. Minimum 0.9 s between retaliations. Plays `entity.llama.angry`.

### Milk (long cooldown)
- The trader checks every 0.2 s whether a **negative** effect exists, using a read-only mirror of `classes/status_cleansing.gd`'s candidates (status nodes, registered effects, legacy Buffs with `is_negative_for`).
- If a negative effect exists and the 20 s cooldown is ready, he drinks for 1.1 s (movement ×0.35), then calls `cleanse_negative_effects()`. This is the same one-shot cleanse the copper sword uses: positive effects stay.
- Sound: `entity.wandering_trader.drink_milk`.

### Invisibility potion
- He drinks for 0.78 s (the Witch's drink time), then calls `女巫药水效果.apply_effect(self,"invisibility",self)`: exactly the Witch's effect (6 s, no AI locking, no character-body collision, faded sprite, contact chip damage).
- AI trigger: an enemy within 70, or hurt within the last 1 s. Cooldown 16 s, first use after 5 s. Sound: `entity.wandering_trader.drink_potion`.

### Potion and wall are independent skills
User rule (2026-09-28): "隐身药水和钻墙应该是独立技能" (fully independent).
- Both cooldowns (and milk's) and the drink timer keep ticking during the wall phase.
- He can enter the wall while drinking, and can start the potion while inside the wall. The AI may trigger both in the same frame; manual left/right click are likewise independent.
- A potion that finishes while `wall_phase != NONE` is deferred (`_pending_invisibility`) and applied in `_finish_wall` after collision/metas are restored, because the Witch effect saves the current collision layer (0 inside the wall).
- The held bottle is hidden while it is on the wall side of the clip (`item_outside_wall`); the drink visual is no longer cancelled by hiding in the wall.
- Milk keeps its rule: not inside the wall and not during another drink.

### Wall (入墙, medium cooldown 11 s, first use after 7 s)
- **Wall slots**: every map tile with a physics-layer-1 collision polygon that touches a walkable tile. PortalMap islands use their own layers. Maps without tiles fall back to the arena edges.
- **AI trigger**: an enemy within 60, or hurt within 0.8 s while HP < 60 %.

The phase runs in four steps:
User rule (2026-09-28): "进墙就应该是直接进去，完全进去才消失。然后出来也是直接从墙钻出来". There is no fading.

**Wall surface** (`wall_face_point`): a layer-1 ray from the slot's floor tile against the normal finds the physical wall (World's bounce walls). On maps whose border ring tiles are walkable (Map10x10), this is the arena edge, not the tile seam. It falls back to the tile seam (`WALL.face_point`).

**Clip** (`wandering_trader/wall_clip.gd`): during entering and emerging, the Image gets a runtime copy of its own `set_rgb_color` shader with a world-space half-plane cut injected. Only the floor side of the wall surface is drawn. Instance uniforms (hit flash, facing flip, soft-body warp) keep working, and the original material is restored at the end.
- Do **not** use `clip_children` for this. Its canvas group rewrites the back buffer that World's outside-map mask (`MapClipBackBuffer` + `screen_texture`) samples, so an unclipped copy of the body shows up beyond the arena edge.

The phase runs in four steps:
1. **Entering**: he walks straight, at constant speed and fully opaque (`wall_entry_speed` 150 px/s, 0.25–1.4 s), from where he stands to a point behind the wall surface. That point is deep enough that his whole drawn body (sprite rect × 1.12 + 2 px) is behind it. The body disappears into the wall as it crosses. Collision is off, there is no AI locking, and `submission_allow_map_escape` is set so World's squeeze rescue and out-of-bounds kill leave him alone past the arena edge. The leashes snap (`entity.leash_knot.break` + `entity.wandering_trader.disappeared`).
2. **Hidden** (2.6 s): starts only once he is completely inside. He is hidden on all peers and untargetable. Damage, hit contacts and knockback are ignored. Plays `block.stone.break` with stone chips at the wall surface. The llamas roam, chase and spit on their own.
3. **Emerging**: the exit is chosen by `WALL.safest_slot`. Slots are ranked by the distance from their floor tile to the nearest enemy (plus ≤ 6 px seeded jitter), and the first slot whose floor can hold his whole body wins (stepping out along the wall normal up to 22 px, then further until the whole drawn body is outside the wall, if that spot is clear). He starts fully inside the wall, straight behind the exit point, becomes visible already clipped, and walks straight out along the wall normal (same speed, minimum 0.3 s). Sounds: `block.stone.hit` + `reappeared`, with chips at the surface.
4. **Finish**: collision, metas and the character material are restored (bit 2 is re-added if invisibility expired meanwhile), and the leashes reconnect (`entity.leash_knot.place`).

**Exit tell** (user request 2026-09-29): `wall_exit_warning` (0.45 s) before the end of the hidden step, the exit slot is chosen and locked (`_warn_exit`), and its wall surface cracks on every peer: three pulses of stone chips spreading along the wall (`_exit_warning_visual`, reliable rpc) plus a quieter `block.stone.hit`. He then comes out exactly there. The tell is readable counterplay; the slot is still the safest one, just evaluated 0.45 s earlier.

### Llama return (user request 2026-09-29)
- When a llama dies, its slot starts `llama_return_cooldown` (20 s; the timer runs in and out of the wall).
- At the start of emerging, the first empty slot whose cooldown is over (`due_llama_slot`) spawns a fresh llama (350 HP, same deterministic name `<trader>_Llama<i>`, the old node is long freed) completely inside the wall, offset ±18/30 px along the wall from his exit (first body-clear spot). It walks straight out with him in the same time, clipped on the same wall surface (`llama.gd` `wt_begin_emerge` / `emerge_clip`), non-solid, untargetable and map-escape-exempt until it is out.
- On `_finish_wall` it gets normal collision and becomes targetable, and the leash reconnects together with the other one. Peers get the clip through the trader (`_llama_clip_remote`), which waits a few frames for the replicated llama.
- One llama per exit. An exit that brings a llama gives no item (items: design draft below).

If the battle stops mid-phase, `finish_wall_phase_now()` pops him out at once.

### Death and lifecycle
- Llamas have HP 350. `retire()` removes them from the Ball group, snaps their leash (`wt_on_llama_lost`) and frees them. No instant respawn (see *Llama return* below). As Type Creature they are not battle characters, so they never count for victory.
- When the trader dies, `owner_lost()` retires the remaining llamas (vanilla trader llamas despawn with him). World resets free them with every Ball.

### Manual control
- Left click: invisibility potion.
- Right click: enter a wall.
- Middle click: milk (only with a negative effect).

### Multiplayer
- Llama spawns go through the auto-spawnable scene path with deterministic names. Spit uses the snowball pattern: authority spawns it locally and via rpc, with deterministic names.
- Sounds are rpc'd with the chosen variant.
- The drink visual, wall hide/show and leash state go by reliable rpc. The leash is drawn locally on every peer.

## Exit items (design draft, not implemented yet)

User request (2026-09-29): every wall exit that does **not** bring a llama back grants one item. All items are things the vanilla wandering trader sells. Two use modes: **instant** (used the moment he steps out) and **held** (at most one in hand; a new item replaces it; the AI uses it on its condition; manual control: key 1). Suggested draw weights in brackets.

| # | Item | Mode | Effect | AI use |
|---|---|---|---|---|
| 1 | Gunpowder 火药 (12) | instant | A primed trap at the exit floor: arms after 0.6 s, fuse hiss, triggers when an enemy comes within 28 px: 30 dmg + knockback, radius 40. Fizzles after 8 s. | on exit |
| 2 | Blue ice 蓝冰 (10) | instant | 3×3 tile ice patch around the exit for 6 s: enemies on it slide (low steering) and move ×0.7. | on exit |
| 3 | Pufferfish bucket 河豚桶 (8) | held | Releases a pufferfish for 6 s that puffs up near enemies; contact = Poison 4 s (Witch poison effect), `entity.puffer_fish.sting`. | enemy within 80 |
| 4 | Pointed dripstone 滴水石锥 (10) | held | Target an enemy within 160: a 0.6 s shadow/dripstone tell above it, then it falls for 25 dmg (vanilla falling dripstone). | enemy within 160 and line clear |
| 5 | Slimeball 粘液球 (10) | held | Thrown ball: 6 dmg, Slowness 40 % for 3 s. | enemy within 140 |
| 6 | Hay bale 干草块 (8) | instant | Feeds the llamas (vanilla: hay heals llamas 10 HP): every living llama heals 60 HP. Re-rolled when no llama is alive. | on exit |
| 7 | Fermented spider eye 发酵蛛眼 (8) | held | Thrown: Weakness 5 s on the target (Witch weakness effect: less outgoing damage). | strongest enemy within 140 |
| 8 | Baked potato 烤马铃薯 (12) | held | Eats it (0.8 s, like the drink): heals the trader 35 HP. | HP < 60 % |
| 9 | Cactus 仙人掌 (10) | instant | Places a cactus block at the exit for 10 s: solid obstacle, contact 5 dmg every 0.5 s (vanilla cactus). | on exit |
| 10 | Tropical fish bucket 热带鱼桶 (12) | held | Releases a flopping tropical fish decoy (60 HP, 4 s): enemy AI within 120 retargets to it. | enemy within 70 |

Open points for the user: which items to keep, instant vs held per item, and whether the numbers fit after a batch simulation. Every item needs its original texture + sound with a `SOURCE.json` (MCP_CONTEXT §4) and must be registered in the classification catalog (§9).

## Numbers

| | value | reference |
|---|---|---|
| Trader HP / Speed | 250 / 80 | Witch 500 / 76 |
| Llama HP / follow speed | 350 / 62 | dog 75, vex |
| Spit damage / speed / interval | 14 / 300 / 2.0 s | snowball 6 / 260 |
| Speed damage | from 130 px/s, ×0.09, cap 40 | |
| Milk cooldown / drink | 20 s / 1.1 s | |
| Invisibility cooldown / first / drink | 16 s / 5 s / 0.78 s | Witch drink 0.78 s |
| Wall cooldown / first / hidden | 11 s / 7 s / 2.6 s | |
| Exit tell / llama return cooldown | 0.45 s / 20 s | |
| Wall walk-in / walk-out | 150 px/s straight, 0.25–1.4 s / 0.3–1.4 s | |
| Leash slack / pull start / pull end | 42 / 60 / 28 world px | |

## Art and sound sources

- Bedrock `resource_pack` @ `736072450c26a7c67f07b1661f29d9a5ebaa14b1`: `entity/wandering_trader.entity.json` (geometry.villager_v2, scale 0.9375, `villager.general/move/raise_arms`), `entity/trader_llama` (geometry.llama.v1.8, creamy/brown + `trader_llama_decor`), `llama_spit` (geometry.llamaspit).
- The baker renders these at 4.265625 px/unit. Frames face LEFT.
- Documented deviations: the llama body is rotated 90° about X as in `llama.setup`; the trader hat brim is skipped (a flat plane viewed edge-on); the decor uses +0.5 inflate; the spit uses a 96×96 canvas at ×2 scale.
- The drink clip uses the vanilla raised-arm pose.
- Sounds: Java Edition equivalents of the Bedrock `.fsb` events (see `audio/characters/流浪商人/SOURCE.json`).
