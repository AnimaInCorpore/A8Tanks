# A8Tanks

`A8Tanks` is a simple tank game for the Atari 800 XL computer, written in 100% assembly.

> Warning: This repository is an AI-assisted testbed.

This project is developed solely by utilizing the automation features of the `jsA8E` emulator.

## Tooling

- Run `npm install` once to install the Node tooling dependencies.
- `node tools/assemble.js` assembles `src/a8tanks.asm` to `build/a8tanks.xex` and converts it to `build/a8tanks.atr`.
- `node tools/run.js --os-rom /path/to/ATARIXL.ROM --basic-rom /path/to/ATARIBAS.ROM` serves `jsA8E`, assembles the source through the current grouped automation API, runs it to the assembled entry breakpoint, and writes build artifacts to `build/`.

## Automation Usage Strategy

The automation strategy is now aligned to current `jsA8E` features:

- Prefer grouped API domains (`system`, `media`, `input`, `debug`, `dev`, `artifacts`, `events`) for all new scripts; keep flat aliases only for backward compatibility.
- Prefer headless integration (`createHeadlessAutomation(...)`) for CI/agent/non-interactive flows; use browser-attached automation only when UI/visual behavior must be exercised.
- Gate workflows with `getCapabilities()` and `getSystemState()` before execution, then branch behavior by supported features (snapshots, URL loaders, progress events, reset `portB` override, artifact schema).
- Use deterministic media/bootstrap paths (`loadRom*`, `mountDisk*`, `runXex*`) with explicit cache controls and reset options where needed.
- Treat `dev.assembleSource(...)` + `dev.runXex(...)` as the canonical build/run path, including structured boot guards (`maxBootInstructions`, `maxBootCycles`, tight-loop detection).
- Subscribe to automation events (`progress`, `pause`, `fault`, `build`, `hostfs`) and persist progress/failure telemetry for each run.
- Capture schema-versioned artifacts on failures (`artifacts.captureFailureState(...)`) and include screenshot/trace/memory ranges for reproducible debugging.
- Use snapshot checkpoints (`system.saveSnapshot()` / `system.loadSnapshot()`) to speed iterative debugging and keep reruns deterministic.

Reference docs:

- `automation/A8E/jsA8E/README.md` (overview + integration guidance)
- `automation/A8E/jsA8E/AUTOMATION.md` (full API contract)

## Run Outputs

`tools/run.js` now tracks jsA8E automation progress and writes the current automation artifacts instead of a hand-built partial snapshot:

- `build/a8tanks.xex`: assembled executable, written whenever assembly succeeds.
- `build/a8tanks.atr`: bootable ATR image converted from the assembled XEX.
- `build/a8tanks.png`: framebuffer screenshot captured from the jsA8E artifact bundle when available.
- `build/a8tanks-run.json`: a schema-v2 jsA8E artifact or failure bundle extended with tool metadata (`toolRun`), build/run summaries, ROM paths, `systemState`, and recorded progress events.

If the breakpoint wait times out or jsA8E reports an automation failure, `tools/run.js` still writes the JSON artifact bundle, preserves any captured screenshot, and exits with a non-zero status.
