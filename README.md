# A8Tanks

`A8Tanks` is a simple tank game for the Atari 800 XL computer, written in 100% assembly.

> Warning: This repository is an AI-assisted testbed.

This project is developed solely by utilizing the automation features of the `jsA8E` emulator.

## Tooling

- Run `npm install` once to install the Node tooling dependencies.
- `node tools/assemble.js` assembles `src/a8tanks.asm` to `build/a8tanks.xex` and converts it to `build/a8tanks.atr`.
- `node tools/run.js --os-rom /path/to/ATARIXL.ROM --basic-rom /path/to/ATARIBAS.ROM` serves `jsA8E`, assembles the source through the current grouped automation API, runs it to the assembled entry breakpoint, and writes build artifacts to `build/`.

## Run Outputs

`tools/run.js` now tracks jsA8E automation progress and writes the current automation artifacts instead of a hand-built partial snapshot:

- `build/a8tanks.xex`: assembled executable, written whenever assembly succeeds.
- `build/a8tanks.atr`: bootable ATR image converted from the assembled XEX.
- `build/a8tanks.png`: framebuffer screenshot captured from the jsA8E artifact bundle when available.
- `build/a8tanks-run.json`: a schema-v2 jsA8E artifact or failure bundle extended with tool metadata (`toolRun`), build/run summaries, ROM paths, `systemState`, and recorded progress events.

If the breakpoint wait times out or jsA8E reports an automation failure, `tools/run.js` still writes the JSON artifact bundle, preserves any captured screenshot, and exits with a non-zero status.
