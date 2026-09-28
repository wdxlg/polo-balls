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
| `tests/test_wandering_trader.gd` | functional test in a real World (item rolls off: `items_enabled = false`) |
| `wandering_trader/items/` | item catalog, display frame, wall crumbs, placed items (gunpowder, blue ice, dripstone, cactus), thrown slime / hay, fish, explosion and heart effects |
| `scenes/creatures/流浪商人_河豚.tscn`, `流浪商人_热带鱼.tscn` | released fish (Type Creature) |
| `Images/characters/我的世界/流浪商人/items/` + `SOURCE_JAVA.json` | vanilla Java 1.21.1 item / block / particle textures |
| `audio/characters/流浪商人/items/` + `SOURCE.json` | 71 vanilla item sounds |
| `tests/test_wandering_trader_items.gd` | item functional test |
| `tests/preview_wandering_trader_items_gpu.gd` | GPU screenshots of the frame, crumbs and every item |

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
- **Arming** (user rule 2026-09-29: "进墙出墙都是正常速度朝着当前移动方向进去，而不用加速"): the trigger only arms the skill (`wall_armed`). He keeps his normal ball movement, with no steering and no speed-up, and goes in at the next wall he runs into (`when_collide` against a non-ball collider, `begin_wall_entry`). He walks on at the speed he had (`_last_requested_velocity`, i.e. Speed × 0.6 for characters) in the direction he had, clamped to at most 60° from the wall normal. The contact point is the clip surface (`entry_slot.contact_face`; slots from `wall_phase.gd` already carry a tile-seam `face`, so do not reuse that key). If he hits no wall within `wall_arm_timeout` (4 s), the skill disarms and retries after 1.5 s.
- **Walk-out**: at the same speed and at the same angle to the exit normal as the walk-in (`exit_direction`). The exit tell and the chips sit where that line crosses the wall (`exit_cross_point`). Afterwards he keeps moving in `exit_direction`.
- **Llamas while the leash is off** (user rule 2026-09-29): normal ball movement (`free_moving`). They start in their own last motion direction, move at their Speed (62) and bounce off walls, characters and the arena edge. Spitting still works. The leashed AI takes over again once the leash reconnects.

The phase runs in four steps:
User rule (2026-09-28): "进墙就应该是直接进去，完全进去才消失。然后出来也是直接从墙钻出来". There is no fading.

**Wall surface** (`wall_face_point`): a layer-1 ray from the slot's floor tile against the normal finds the physical wall (World's bounce walls). On maps whose border ring tiles are walkable (Map10x10), this is the arena edge, not the tile seam. It falls back to the tile seam (`WALL.face_point`).

**Clip** (`wandering_trader/wall_clip.gd`): during entering and emerging, the Image gets a runtime copy of its own `set_rgb_color` shader with a world-space half-plane cut injected. Only the floor side of the wall surface is drawn. Instance uniforms (hit flash, facing flip, soft-body warp) keep working, and the original material is restored at the end.
- Do **not** use `clip_children` for this. Its canvas group rewrites the back buffer that World's outside-map mask (`MapClipBackBuffer` + `screen_texture`) samples, so an unclipped copy of the body shows up beyond the arena edge.

The phase runs in four steps:
1. **Entering**: from the wall contact he walks straight on, at his normal speed and fully opaque (capped at 3 s), to a point behind the wall surface. That point is deep enough that his whole drawn body (sprite rect × 1.12 + 2 px) is behind it. The body disappears into the wall as it crosses. Collision is off, there is no AI locking, and `submission_allow_map_escape` is set so World's squeeze rescue and out-of-bounds kill leave him alone past the arena edge. The leashes snap (`entity.leash_knot.break` + `entity.wandering_trader.disappeared`).
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
- **Haochen copy of a llama**: its Master is the copier (a plain ball without leash properties). `trader()` only returns a real trader (`wt_leash_active`). A llama with `haochen_copy` meta, or with a living non-trader Master, is a free agent (`is_free_agent`): it does not retire, and it moves and spits freely. This fixes the `float(null)` crash on `leash_slack`.
- Llamas have HP 350. `retire()` removes them from the Ball group, snaps their leash (`wt_on_llama_lost`) and frees them. No instant respawn (see *Llama return* below). As Type Creature they are not battle characters, so they never count for victory.
- When the trader dies, `owner_lost()` retires the remaining llamas (vanilla trader llamas despawn with him). World resets free them with every Ball.

### Manual control
- Left click: invisibility potion.
- Right click: enter a wall.
- Middle click: milk (only with a negative effect).
- Key 1: use the held item now.

### Multiplayer
- Llama spawns go through the auto-spawnable scene path with deterministic names. Spit uses the snowball pattern: authority spawns it locally and via rpc, with deterministic names.
- Sounds are rpc'd with the chosen variant.
- The drink visual, wall hide/show and leash state go by reliable rpc. The leash is drawn locally on every peer.

## Exit items (物品, user request 2026-09-29)

Every wall exit rolls one item (equal weights, including exits that bring a llama back) into the **item display frame** (物品展示框, `items/frame_view.gd`) that hangs under him. The frame is small (8 px) and **only shown while he holds an item** (user rule 2026-09-29). It uses the vanilla item-frame texture and sounds (`entity.item_frame.add_item` / `remove_item`), is drawn in world space, and hides with his body while he is behind a wall surface.

**Using an item** (user rule 2026-09-29, every item): the item leaves the frame (the frame hides), goes into his hand with the raised-arm pose and is swung a little (±0.3 rad, `item_swing_time` 0.42 s). The effect happens at the end of the swing, and the item vanishes from the hand at that moment. For the potato, the eating (0.96 s) starts after the swing and the potato vanishes when it heals. If he goes into a wall, is stunned or loses damage output mid-swing, the item goes back into the frame. Drinking and swinging never overlap.

**Nothing of his disappears on its own** (user rule 2026-09-29): placed items have no timer (`life = INF`). They stay until used up (gunpowder explodes) or the battle is reset, and they keep working (with his team) even if the trader node is gone. Fish never dry out, and there is no fish cap (`fish_max_each = 0`). Fish only die in combat or together with him, like the llamas. 干草块 is only rolled while a llama is hurt, and 马铃薯 only while he is hurt. A new roll replaces an unused item. Manual control: key 1 (`controlled_item_action`) uses the held item at once. The fermented spider eye from the draft was dropped.

| Item | Trigger | Effect |
|---|---|---|
| 火药 Gunpowder | dropped at his feet 0.6–2.4 s (random) after the exit | Arms after 0.4 s; an **enemy** stepping on it lights a 0.2 s fuse (vanilla fuse sound), then it explodes: **50** damage to enemies within 22 px plus knockback, vanilla explosion sprite + sound. His own side never sets it off. No timer. The pile is drawn 12 px with a contact shadow and smokes lightly (vanilla generic poof frames, 3.5 puffs/s, white → off-white grey, random angle and small random size); once triggered the smoke pours out (110 puffs/s plus a gush) and each puff goes white → black. Puffs already out finish after the explosion. |
| 蓝冰 Blue ice | placed 0.3 s after the exit, just inward of the wall | 3×3 blocks (33 px, one block = 11 px at character scale) on the floor layer (relative z −1 = absolute −3: above the map tiles (−4), under every character (−2)), no timer. **Neutral** (user rule 2026-09-29): anyone on it, the trader and his llamas included, gains extra speed along its own movement (+240 px/s², up to 1.3× its base speed) through the shared `surface_motion_velocity` channel. Off the ice the boost decays at 70 px/s². Hitting a wall or obstacle while the boost is still ≥ 20 px/s deals 6–30 damage (scaled by the remaining boost), and the boost bounces off at 45 %. |
| 河豚桶 Pufferfish bucket | 0.3 s after the exit | Releases a pufferfish (`scenes/creatures/流浪商人_河豚.tscn`): a killable Creature summon on his team, **50** HP. See the fish rules below. Touching an enemy stings it for 10 (14 while puffed) damage plus Poison 4 s, with a 0.7 s cooldown per target. It puffs up while an enemy is within 34 px. |
| 热带鱼桶 Tropical fish bucket | 0.3 s after the exit | Releases a tropical fish (`流浪商人_热带鱼.tscn`): **75** HP, on his team. Same movement as the pufferfish. **Collision damage from its own speed** (user rule 2026-09-29): ramming an enemy deals speed × 0.05 (0 below 60 px/s, cap 22; a 300 px/s hop = 15) plus a knockback along its motion, with a 0.5 s cooldown per target. It does not poison. |
| 滴水石锥 Pointed dripstone | the next time he touches a wall (`when_collide`) | He swings it, then a spike grows out of the wall point he touched, along its normal (14 px long, no timer). It is **neutral**: anyone who touches it, the trader and his llamas included, takes 18 damage plus a small push, with a 0.6 s cooldown per unit (he gets 0.8 s of grace right after placing it). If he touches no wall within 12 s, it is set down behind him as a floor spike. |
| 粘液球 Slimeball | thrown when an enemy is within 150 px with a clear line (after 10 s: any enemy in range) | Real ballistic throw (user rule 2026-09-29 "抛物线弹道"): launched with the velocity that reaches the aim point after the flight time under screen-space gravity 520 px/s², so it rises and then drops; a miss falls a little past the aim (1.3× flight) and splats. It leaves a trail of slime-ball crumbs (45/s) that fall. It hits the first enemy it touches: 10 damage, knockback along its flight and Slowness 3 s, plus a slime crumb splash and `entity.slime.attack`. The first wall or obstacle (or the arena edge) splashes and bounces it back at half speed; a second one ends it. |
| 干草块 Hay bale | 0.3 s after the exit | Thrown on a spinning parabola onto the most hurt llama, following it. Heals **70**, with vanilla heart particles and hay crumbs. |
| 马铃薯 Baked potato | at once on exit | Eaten through the drink path (0.96 s, three vanilla eat sounds plus burp, potato crumbs). Heals **40**. |
| 仙人掌 Cactus | placed behind him (or beside him) on a clear floor spot 0.6–2.4 s after the exit | 14 px solid block (collision layer 1, group `WTItemObstacle`, so it never counts as a wall to walk into), no timer. It is **neutral**: touching its **left or right** side deals 8 damage plus a sideways push, with a 0.5 s cooldown per unit. The top and bottom are harmless. |

**Fish** (`items/fish.gd`, on `mc_mob_base`):
- Out of water it flops: gravity (900 px/s²) pulls it down to the arena floor, where every landing throws it up again with a random medium jump (210–320 px/s).
- Horizontal drift is 40–70 px/s, like the anvil. It bounces off characters, obstacles and the arena walls.
- The body tumbles freely: landings and bounces kick its spin, and gravity swings it.
- It never dries out and there is no cap (see above).
- The inherited body hitbox is disabled, so the pufferfish sting / tropical fish ram are the only contact damage.

**Wall crumbs** (`items/crumbs.gd`, user rules "墙壁的小方块粒子" and 2026-09-29 "进墙粒子是在进墙的时候触发…出墙也是在出墙的时候触发…受重力影响"): small squares cut from the wall tile's own atlas region (`wall_source`: the tile just behind the surface point, falling back to vanilla stone), like vanilla terrain particles. Entry and exit crumbs are a **stream** (`CRUMBS.stream`), emitted on every peer at 60/s for exactly as long as his drawn body straddles the clipped wall surface: while he walks in and while he walks out, not once he is fully hidden or fully out. They spawn along the crossing line across his body width, fly out of the wall and fall. The exit tell also pulses crumbs. Every crumb has its own age, falls under gravity 380 px/s² with drag, and fades and shrinks smoothly at the end of its life. The same crumbs are used for the ice, cactus, dripstone, hay, slime and potato. The stone break sound now plays at the wall contact, together with the entry crumbs.

**Placed items** (`items/placed.gd`): authority-owned, spawned on every peer by rpc with deterministic names, group `MCWanderingTraderItem`, and they fade out at the end of their life.
- Their damage goes through `receive_positional_damage` with the trader as the source, and MC hit sounds follow §1.

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
| Wall walk-in / walk-out | his normal speed and direction (≤ 60° to the normal), ≤ 3 s each; armed ≤ 4 s | |
| Leash slack / pull start / pull end | 42 / 60 / 28 world px | |
| Gunpowder / dripstone / cactus side / slime | 50 / 18 / 8 / 10 damage | |
| Pufferfish / tropical fish HP | 50 / 75 | llama 350 |
| Tropical fish ram | own speed × 0.05, from 60 px/s, cap 22 | |
| Hay / potato heal | 70 / 40 | |

## Art and sound sources

- Bedrock `resource_pack` @ `736072450c26a7c67f07b1661f29d9a5ebaa14b1`: `entity/wandering_trader.entity.json` (geometry.villager_v2, scale 0.9375, `villager.general/move/raise_arms`), `entity/trader_llama` (geometry.llama.v1.8, creamy/brown + `trader_llama_decor`), `llama_spit` (geometry.llamaspit).
- The baker renders these at 4.265625 px/unit. Frames face LEFT.
- Documented deviations: the llama body is rotated 90° about X as in `llama.setup`; the trader hat brim is skipped (a flat plane viewed edge-on); the decor uses +0.5 inflate; the spit uses a 96×96 canvas at ×2 scale.
- The drink clip uses the vanilla raised-arm pose.
- Sounds: Java Edition equivalents of the Bedrock `.fsb` events (see `audio/characters/流浪商人/SOURCE.json`).
