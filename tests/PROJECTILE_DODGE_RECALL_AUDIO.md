# Projectile dodge coverage and Allay recall audio

## Contact fixes
13 previously uncovered flight-contact paths now invoke `try_full_projectile_dodge(self)` before hit consumption, status effects, damage, or hit feedback: trident, water blob, web pellet, ghast fireball contact, rain drop, sad tear, tired Z, heavy text, Viola text/fire projectile, builder brick, war goddess fire slash, and collector money.
Dodged shots continue rather than being treated as blocked. Trident selects contacts in sweep order before the nearest wall; tears and Viola fire retry the ray excluding dodged bodies, preserving wall collision. No blanket owner-based ranged immunity is added. Melee, ground fire and landed/existing explosions are not newly given guaranteed projectile evasion. Existing probability-first enderman dodge, clone probabilities and grace remain unchanged. The common projectile dodge interface also benefits other characters already exposing it.

## Recall sounds
The previous synthesized WAVs were rejected and have been replaced by byte-identical Minecraft Java 1.21.1 assets from Mojang's official CDN. Spin uses `item.trident.riptide_1` / `item/trident/riptide1.ogg`, pitch 1.0. Release uses `entity.wind_charge.wind_burst` / `entity/wind_charge/wind_burst1.ogg`, with the vanilla sounds.json event pitch of 1.25. No synthesized layers, retiming, cropping, or added notes. SHA-1 values and source URLs are recorded under `audio/characters/我的世界/allay/recall_vanilla/sources.json`. The old WAVs and generator are no longer used.

Dedicated native sound events use the existing authority + reliable RPC pathway, at 0 dB. One spin event at transition into spin (not once per note/frame). Release event only when at least five actual notes are consumed and a wave spawns, regardless of hitting an enemy. Existing actual-damage hurt/crit feedback remains separate. Radius, times, hit window, damage and knockback are unchanged.

## Verification
- extended projectile dodge: 25/25 (real enderman with random dodge disabled; water/web/trident/brick/fire slash/text; no damage, no consumption/status bookkeeping; ordinary melee still damages).
- Allay recall: 43/43 (phase triggers, original imported OGG assets, event pitches, actual playback at 0 dB, no false release below five notes, existing recall contracts).
- drowned damage audio: 24/24.
- drowned hand/blur policy: 101/101.
Total: 193 assertions pass. Changed GDScript diagnostics checked. Headless editor imported both original OGGs. Existing shader filename case warning remains unrelated. No subjective gameplay mix audition or two-peer network validation performed.
