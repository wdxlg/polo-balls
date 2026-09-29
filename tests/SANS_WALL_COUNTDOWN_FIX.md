# Sans Boss wall attacks and countdown presentation

## Changes
- Rolling wall bones must pass the outgoing viewport edge with their full visual bounds (including head width) before retiring. Camera pan/zoom and all four travel directions are included. Entry offscreen is not confused with exit.
- Final moving bones no longer expire at the old three-second lifetime. Stationary corridor bones retain their phase lifetime. Corridor transition waits for live scrolling bones to leave before replacing them.
- Shared `sans_wall_slots.gd` tracks map + side + attack token using live effect nodes, not a guessed timer. One train can have multiple spaced bones; independent trains/ordinary spikes/full-wall spikes cannot share the same occupied wall. The opposite wall remains independent. Queued/deleted effects release their slot, and rolling skill lock remains until the actual train retires. RPC transmits the train token.
- Final countdown no longer disables idle sway. Slam, scrolling, corridor and windmill events select native directional hand gestures, then return to idle. Gesture timeout follows the same paused battle clock. No attack or damage changes are introduced through visuals.
- Fullscreen black is now a world-canvas backdrop at z=-1, beneath characters, rather than a foreground CanvasLayer. Its transform cancels camera movement/zoom. Countdown text remains in foreground HUD layer 128. Ending/interruption restore original map, camera and character layers as before.

## Validation
- `test_sans_wall_screen.gd`: 23/23.
- `test_sans_sway.gd`: 12/12.
- `test_sans_final.gd`: 68/68.
- Total: 103 assertions pass. Changed scripts have zero reported LSP diagnostics.
- Short real GPU preview (GL compatibility, 540x960): opening 0.25 s, hand gesture 1.65 s, subsequent idle 2.35 s captured. The opening screenshot was viewed: Sans and combatants are visible against the black backdrop. Preview rerun exits 0 without script errors. Not a full-duration GPU/network acceptance test.
- Initial preview inherited a freed-unit test-harness lookup; local preview now prunes invalid weak actors before calling the parent harness. Existing ObjectDB exit-leak and resource UID/case warnings are not claimed fixed.
