# 矿车 / Minecart — implementation and verification

> **当前版本已改为一格一轨，以下旧版网络说明为历史记录。**
> 最新规则和验证见项目根目录 `MC_MINECART_GRID_FIX.md`：绝对层级车体5/轨道1，真实圆弧转弯，到站随机方向恢复普通移动；必须离开后重新接近才入轨。同格去重，动力状态只升级不降级，预览也不叠加第二层轨道。


Implemented in `scenes/characters/我的世界/矿车.tscn`; behavior, shared pickups and bounded effects live in `scripts/characters/我的世界/minecart/`.

## Current: permanent connected network — 2026-09-18

**Canonical current rules and validation: `MC_MINECART_NETWORK.md`.** The later user request supersedes timed-lane gameplay below:

- Eight-second lay-track attacks, one-second preview, at most ONE 90-degree elbow per construction.
- Only the middle 40%-60% of the newly laid path is powered. Gradual normal acceleration 140/s², powered acceleration 900/s², speed 120→620; higher speed means higher damage. Hits/corners conserve speed.
- Battle-local permanent nodes/edges, no TTL or oldest-track eviction. Both ends snap/connect within 24 units, terrain permitting.
- Approach either port within 20 units to board and traverse connected edges to the other end; reverse boarding works without spending a construction attack.
- Geometric crossings alone are not junctions. Visited edges terminate loops. Explicit battlefield cleanup removes the network.
- Current tests: `test_mc_minecart.gd`, `test_mc_minecart_live.gd`, retained `test_mc_minecart_directions.gd`. Animated real-GPU showcase: `tests/minecart_network_preview.gif`.

## Superseded timed-lane redesign — 2026-09-18

**The current rules are documented in `MC_FRONTIER_CHARACTERS.md`. All gameplay reports below are historical.** The user requested a redesign: real terrain-clipped rail lanes, powered acceleration, kinetic-energy damage and endpoint/manual braking now replace the three-wall bonus-round and random-pickup system.

- 500 HP, base attack 40; no idle contact damage. First automatic planning after ~1.5s, subsequent idle interval 4.5s, windup 0.7s.
- Shared 16-second lanes: 2 per builder, 8 arena-wide. Other carts may board a lane; rails are not consumed pickups.
- 4s powered / 2s unpowered. Speed 100 → 560, acceleration 720, braking 1200.
- Damage = current base attack × (0.35 + 2.35 × speed fraction²). A confirmed impact spends 45% speed; one hit per enemy per second.
- Endpoint detector braking, power loss, leaving/losing the lane, terrain collision, manual Skill or control interruption ends travel. **No wall reflection, bonus round or rail damage-reduction buff remains.**
- The original 64-direction, 576-frame model/atlas remains unchanged. Existing direction and live tests have been updated to the new contract, not deleted.

## Historical record (not current gameplay requirements)

### Retired three-wall rules

- 500 HP; no ordinary contact attack. Five seconds in idle starts a stationary one-second windup.
- Rush at 480 world units/s. Each wall ends one leg and reflects direction; the third wall ends the round. Each enemy may be damaged once per leg, for 80 damage before shared combat modifiers.
- If every leg actually damages an enemy's HP or shield, earn exactly one bonus round: another one-second windup followed by three 100-damage legs. Bonus rounds cannot earn another bonus. Dodge/immunity/full rejection does not count as damage.
- One shared arena rail manager, not one spawner per cart: one spawn attempt every ten seconds, at most three rails. Spawn points are map-bounded, terrain-clear and accessible near a live cart. Failed placement waits for the next interval; a full arena cannot accumulate a spawn burst.
- A picked-up rail is consumed. Idle pickup begins a windup; pickup during an existing charge/rush empowers it without resetting time, leg count or bonus eligibility. An already-powered cart leaves other rails alone.
- Ten percent incoming damage reduction applies only during rail-powered rushing, including shield and raw-health spatial routes. It composes once with normal reduction and does not apply during windup. An earned bonus retains rail power, but its windup is not protected.
- Shared knockback controller: 95 world-unit travel, speed 420, 0.12-second stun, no extra collision damage; immunity/control rules remain in force.
- Eight-second maximum rush lifetime, 0.06-second corner-contact debounce, interruption on stun/attack disabling. Combat pause freezes timers, movement and effects. Original collision masks are restored, including carts created while large-battle mode was already active.

## Presentation and integration

**Current directional model animation:** Runtime body and selector preview now use **64 native-model directions**, each with one neutral pose plus eight rolling samples (576 frames total). This follows the guardian's offline model-to-SpriteFrames approach. The original minecart inventory icon is retained only as a source asset, not used as the body.

The model, 64×32 entity skin, and `animation.minecart.move.v1.0` root channels come unchanged from Mojang's official `bedrock-samples` commit `736072450c26a7c67f07b1661f29d9a5ebaa14b1`. Original PNG/JSON source hashes are in `MC_MINECART_ASSETS.json`; generated atlas/frame hashes, common pivot, projected headings and bounds are in `Images/characters/我的世界/矿车/minecart_turns.json`. The model-render PNGs are **derived renders**, not claimed to be byte-identical files from the game. The native animation's rail-offset/rail-pitch inputs are supplied with a small periodic profile for this arena's free movement. No painted parts or invented wheel bones were added.

Normal movement plays a distance/speed-driven rolling cycle, with a brief hold to avoid idle-frame flicker between physics and render ticks. Windup remains physically stationary while the model rocks. Dash animation runs faster. Idle/charge turns use shortest-angle interpolation across 64 views; launch and wall reflection immediately align with the rush heading. Combat stop and SceneTree pause freeze both heading and animation phase. Real collision geometry, damage, timers and knockback remain unchanged. Ordinary movement heading, animation phase and speed are included in visual snapshots; the non-authority animation branch is tested, but two-peer transport is not.

Rail and particle art still use the original powered/unpowered rail PNGs and particle atlas. No self-drawn SVG, geometric aura, arrow or line trail was restored. Existing original sound events are unchanged. The 4096×2304 model atlas is shared by all carts; nearest filtering, no mipmaps and disabled alpha-border recoloring preserve the validated frame pixels.

### Rebuild and preview

The baker uses the existing shared `mc_native_assets/bake_native_mobs.py` rasterizer. Python dependencies are isolated in the ignored local `.venv`; game runtime has no Python/3D dependency.

```powershell
python scripts/training/mc_minecart_assets/fetch_assets.py --check
# To recreate the local bake environment if absent:
python -m venv scripts/training/mc_minecart_assets/.venv
& scripts/training/mc_minecart_assets/.venv/Scripts/python.exe -m pip install -r scripts/training/mc_minecart_assets/requirements.txt
& scripts/training/mc_minecart_assets/.venv/Scripts/python.exe scripts/training/mc_minecart_assets/bake_minecart.py
godot --headless --path . --script res://tests/test_mc_minecart_directions.gd
godot --path . --rendering-method gl_compatibility --script res://tests/preview_mc_minecart_directions.gd
& scripts/training/mc_minecart_assets/.venv/Scripts/python.exe scripts/training/mc_minecart_assets/package_preview.py
```

The GPU showcase saves 64 frames and `tests/minecart_direction_capture/minecart_directions.gif`. It deliberately cycles headings on Map10x10 for readable close-up views; it is not an autonomous combat benchmark. Original assets remain Mojang/Microsoft copyrighted, not open-license artwork.

Chinese/English names are present in both CSV and compiled catalogs. Minecart provides a bilingual armor-stand summary and selector preview. Host-authoritative rail snapshots include monotonic revisions and join-state requests; cart visual snapshots and reliable effect events use existing project conventions. **Two-peer multiplayer transport has not been tested.**

## Direction-animation verification — 2026-09-17

- **84/84 direction/animation checks**: all 64 views; neutral + rolling poses; stable collider/pivot; all 576 imported pixel hashes; real-motion frame cycling; stationary settling; windup; faster dash; immediate cardinal/diagonal reflection; shortest-angle wrap; both pause modes; movement disabling; snapshot initialization and non-authority animation continuation.
- **81/81 mechanism/native-source checks**, **8/8 autonomous live checks** (880 armor-stand damage, 3 spawned rails including fixture, 3-wall maximum).
- **63/63 armor-summary checks**, **3,881 name checks with 0 failures**, 809-key translation catalog consistent.
- **12/12 original source hashes** and **5/5 particle-definition UV checks** pass. Atlas/frame bounds and projected headings validated during baking.
- Cart code, scene, direction test and GPU-preview test diagnostics returned **0 errors/warnings**. The 64-frame actual GPU showcase was inspected.
- Existing ObjectDB shutdown-fixture warning remains. This is not a claim of a full repository-suite pass or completed two-peer testing.

## Native-asset correction verification (before directional animation) — 2026-09-17

- Pinned-source verification: **9/9 SHA-256 hashes**, plus **5/5 particle UV definitions**.
- Updated minecart regression: **78/78** (original 60 mechanic checks plus 18 native-asset/render checks).
- Automatic live battle: **8/8**, including physical pickups, wall reflections and damage; 880 test-target damage, 3 rail spawns, 3-wall maximum.
- Armor-stand regression: **63/63**; character names: **3,881 checks, 0 failures**, 134 scenes / 809 translation keys.
- Translation catalog check: **809 keys**, all character scenes covered.
- New cart scripts and test diagnostics: **0 errors/warnings returned**. Runtime script/scene search found **no references to the removed SVGs**.
- Four-state GPU preview regenerated with the native assets and visually inspected. Ordinary/cart/rail artwork and particle silhouettes now come from the official originals, not the old vector presentation.
- Existing shutdown fixture warning remains (103 ObjectDB instances in the live run); no new runtime errors appeared in the inspected final test outputs. Two-peer network transport was not tested.

## Gameplay verification before native-asset correction — 2026-09-17

Godot 4.7.2, current Windows project:

| Check | Result |
| --- | --- |
| `test_mc_minecart.gd` | 60/60 assertions; includes actual swept geometry and terrain reflections |
| `test_mc_minecart_live.gd` | 8/8; automatic state machine, real rail pickup, damage and repeated wall contacts under continuous engine ticks |
| Latest live observation | 880 damage to test armor stand; 3 total rail spawns including the initial fixture; maximum 3 walls |
| `test_mc_armor_summaries.gd` | 63/63; all 19 Minecraft scenes |
| `test_character_name_translations.gd` | 134 scenes, 809 keys, 3,881 checks, 0 failures |
| `sync_translation_catalog.py --check` | 809 keys; all character scenes covered |
| `test_mc_bat_shield_collision.gd` | 62/62; preserves 0.25-second shield timing and same-cohort collision rules |
| `test_watermark_follow.gd` | 42/42 |
| New scripts / scene / tests editor diagnostics | 0 errors or warnings returned |

`preview_mc_minecart.gd` runs with an actual graphics renderer and saves `tests/minecart_preview.png` plus a small JPEG. Four deliberately arranged presentation states: idle, windup, powered rush, powered bonus rush. These screenshots are not a substitute for the independent gameplay tests. The four-state GPU capture was visually inspected. Pixel coordinates account for the project's viewport stretch.

Example commands (substitute the local Godot executable):

```powershell
godot --headless --path . --script res://tests/test_mc_minecart.gd
godot --headless --path . --script res://tests/test_mc_minecart_live.gd
godot --path . --rendering-method gl_compatibility --script res://tests/preview_mc_minecart.gd
python scripts/training/sync_translation_catalog.py --check
```

Tests reuse the existing bat-world fixture, so their summary prefix is `BAT RESULT`. Existing fixture runs can report ObjectDB cleanup warnings at shutdown (103 in several runs). The first minecart run additionally reported 10 resources in use; later repeat/verbose runs did not reproduce that resource error. No assertion failures occurred in the final checks listed above. The previously identified generic localization-index failure (`move into internal subtree`) was not modified or revalidated by this task; this is not a claim that the entire repository test suite passes.
