# A8Tanks Start Screen Follow-up

## Objective
Match the game start screen to `a8tanks.jpg` as closely as possible using the jsA8E automation flow.

## Current status
- `src/a8tanks.asm` now uses a generated ANTIC mode E bitmap start screen instead of blocky text-mode drawing.
- `tools/generate_start_screen.js` regenerates the bitmap display list, image data, and per-scanline color tables from `build/a8tanks-ref.png`.
- BASIC is explicitly disabled in init with `PORTB=$FF` while keeping OS ROM and self-test state safe for XL/XE.
- Build compiles successfully with `node tools/assemble.js`.
- Live headless screenshot capture validates the rendered screen after the program runs.

## Latest outputs
- Blueprint image: `a8tanks.jpg`
- Cropped/resized reference used for comparisons: `build/a8tanks-ref.png`
- Previous best text/block attempt: `build/a8tanks-new4.png`
- Latest bitmap screenshot: `build/a8tanks-bitmap-live.png`
- Latest side-by-side compare: `build/a8tanks-compare-bitmap-live.jpg`

## Quantitative comparison (RMSE vs `build/a8tanks-ref.png`)
- `build/a8tanks-new4.png`: `0.396795`
- `build/a8tanks-bitmap-live.png`: `0.201641` (current best)

## Most relevant code regions
- Init and BASIC disable: `src/a8tanks.asm` near `INIT`
- Display list: `src/a8tanks.asm` near `MY_DISPLAY_LIST`
- Bitmap payload: `src/a8tanks.asm` near `BITMAP_DATA`
- Scanline color tables: `src/a8tanks.asm` near `START_COLBK`, `START_PF0`, `START_PF1`, `START_PF2`
- Regeneration script: `tools/generate_start_screen.js`

## Remaining visual gaps
- Normal-width playfield leaves Atari border/edge artifacts compared with the full-width reference crop.
- Row-wise four-color quantization is recognizable but still rough in the tank shading and logo edges.
- Prompt is currently part of the static bitmap; it does not blink.

## Recommended next steps
1. Consider a wide-playfield bitmap pass if matching the full 336px screenshot width matters more than edge cropping risk.
2. Improve quantization with semantic/fixed color anchors for sky, logo fill, logo outline, tank green, and track black.
3. Add prompt blinking by masking prompt rows or swapping prompt-row palette entries during `UPDATE_TITLE_ANIMATION`.
4. Keep validating with live headless capture, not only `tools/run.js`, because `tools/run.js` captures at the entry breakpoint.

## Reproduction commands
1. Regenerate the start screen from the current reference:
   - `node tools/generate_start_screen.js`
2. Build:
   - `node tools/assemble.js`
3. Capture live screenshot headlessly:
   - use `automation/A8E/jsA8E/headless.js`
   - set a breakpoint at the assembled entry point before `api.dev.runXex(...)`
   - clear the breakpoint, resume, wait about `120frames`
   - capture with `api.artifacts.captureScreenshot({ encoding: "bytes" })`
4. Compare:
   - `magick compare -metric RMSE build/a8tanks-bitmap-live.png build/a8tanks-ref.png null:`

## Notes
- ROMs used in this workspace are at:
  - `../a8e/ATARIXL.ROM`
  - `../a8e/ATARIBAS.ROM`
