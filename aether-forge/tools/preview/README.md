# Offline preview

Runs the game's own shared Luau modules (Rigs, AnimCore, Clips, ArenaLayout) outside Roblox with a small
Vector3/CFrame shim, and renders the result with three.js in headless Chromium.

- `bake.luau <aether-forge dir> <out.json> [sheet...]`: poses -> JSON (needs a Luau runner that exposes
  `readfile`, `writefile`, `loadchunk` and `ARGS`)
- `render.cjs <frames.json> <outDir> <three.min.js> [view] [cols]`: JSON -> PNG contact sheets
  (views: front, side, back, top, game, game2, threeq)
- `test_animator.luau <aether-forge dir> [-v]`: drives the real client RigAnimator through a full move
  chain and reports NaNs, per-frame joint jumps and suspected IK flips
