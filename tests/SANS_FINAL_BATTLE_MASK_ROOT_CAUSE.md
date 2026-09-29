# Sans final-battle visibility: actual map geometry fix

Supersedes the earlier opening-only blackout diagnosis in SANS_WALL_COUNTDOWN_FIX.md.

## Root cause
The runtime SansFinal10x10 TileMapLayer has no painted cells. return_map_world_rect already honored sans_final_rect, so the camera/border looked correct, but MapTileGeometry.from_layer still returned zero floor regions. Both the opaque outside mask and out-of-bounds checks therefore treated the actual arena as outside. This persisted after the opening and throughout dynamic corridor movement. Raising character z or merely moving the transition blackout was insufficient.

## Fix
MapTileGeometry.from_layer now handles the explicit sans_final_rect metadata before normal cell caching: one current rectangular floor plus four exterior wall strips. It is recomputed from current metadata, so narrowing/extension cannot keep a stale empty/cached shape. Ordinary tile-painted maps and PortalMap logic remain unchanged.
During the entire final controller lifetime, hide VS/team names, interaction text, creator/dead-save watermark, character-dialogue area, rotation-roster HUD and extra training clock. Newly created HUD nodes are caught too; each original visibility is saved and restored on normal completion/interruption. Countdown remains visible. In-map combat feedback, characters and gameplay controls are not globally disabled.

## Verification
- test_sans_final: 83/83, including floor region, no opaque polygon overlap inside the arena, corridor expansion and HUD restoration/suppression.
- test_sans_wall_screen: 23/23; test_sans_sway: 12/12. Relevant total 118 assertions pass.
- Full real GPU run using live_sans_battle_mask_fix.gd: 46.148-second final completed, max rightward travel 1969.355, original map restored, immunity false, exit code 0. Six captures at 2.3, 9.2, 18.0, 26.6, 31.6 and 45.5 seconds. No mask/HUD assertions or script errors. The 9.2-second scrolling and 18-second corridor images were explicitly viewed: actors visible, VS/name banner/watermark absent, countdown visible.
- Changed geometry/controller diagnostics: zero errors/warnings reported.
- Supplemental portal tests printed 28/28 and 15/15, but their scene-catalog scans also logged Minecraft resource preload errors; these are not counted as clean regression passes and were not addressed by this patch.
- This is a local real-rendering run, not a two-peer network test.
