# A8Tanks

`A8Tanks` is a simple tank game for the Atari 800 XL computer, written in 100% assembly.

This project is developed solely by utilizing the automation features of the `jsA8E` emulator.

## Tooling

- Run `npm install` once to install the Node tooling dependencies.
- `node tools/assemble.js` assembles `src/a8tanks.asm` to `build/a8tanks.xex`.
- `node tools/run.js --os-rom /path/to/ATARIXL.ROM --basic-rom /path/to/ATARIBAS.ROM` serves `jsA8E`, assembles the source through the emulator automation API, runs it, and writes build artifacts to `build/`.
