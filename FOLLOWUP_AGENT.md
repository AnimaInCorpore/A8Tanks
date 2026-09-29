# A8Tanks Follow-up Notes

## Current status
- `src/a8tanks.asm` is a complete, playable two-tank artillery game (title screen, 1P vs CPU / 2P, wind, destructible terrain, best-of-rounds scoring, sound). See `README.md` for controls and architecture.
- The program is independent of the OS ROM after start-up (`PORTB=$FE`, own NMI vector at `$FFFA`). It must therefore keep touching hardware registers directly (no shadow registers).
- Generated blocks in `src/a8tanks.asm` are produced by `tools/generate_start_screen.js` (title) and `tools/generate_assets.js` (font, tables, game display list).

## Memory map
- `$2000-$4FFF` code and tables (`GAME_DL` is pinned at `$4C00`: ANTIC display lists must not cross a 1K boundary)
- `$5000-$54FF` variables, `TEXTBUF` (HUD rows + title prompt)
- `$6000-$7F9F` game bitmap (two 4K-safe halves, `SCREEN_A` / `SCREEN_B`)
- `$8000-$AB7F` title display list, bitmap and palette tables
- `$B000-$B7FF` player/missile RAM, `$B800` character set (ASCII codes used directly as screen codes)

## Testing without ROM files
The jsA8E headless runtime only starts with an OS and BASIC ROM loaded, but this game does not need the real OS. For automated checks use a 16K stub `ATARIXL.ROM` whose reset vector points at `SEI/CLD/JMP $2000` and an 8K dummy `ATARIBAS.ROM`, call `api.system.reset({ portB: 0xFF })`, write the XEX segments with `api.debug.writeRange(...)`, then `api.system.start()`. (Reset clears RAM under the BASIC window, so load after the reset.) Joystick and console keys can be driven with `api.input.setJoystick(...)` / `api.input.pressConsoleKey(...)`.

## Ideas not done yet
- Blinking "PRESS START" on the title.
- Tank movement / fuel, multiple weapons, per-tank health.
- Falling animation when the ground under a tank is destroyed (tanks currently snap to the new surface).
- Pause on `OPTION`.
