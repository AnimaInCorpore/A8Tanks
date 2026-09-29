#!/usr/bin/env node
"use strict";

// Regenerates the font and lookup-table blocks embedded in src/a8tanks.asm.
//   node tools/generate_assets.js [target.asm]

const path = require("path");
const { replaceBlock } = require("./lib/asm_blocks");

const repoRoot = path.resolve(__dirname, "..");
const targetPath = path.resolve(repoRoot, process.argv[2] || "src/a8tanks.asm");

const CHARSET_ORG = 0xb800;
const CRATER_RADIUS = 9;

// 5x7 glyphs, one string per scanline ('#' = pixel).  The character code is
// plain ASCII so the game can use .TEXT strings directly as screen data.
const GLYPHS = {
  " ": [".....", ".....", ".....", ".....", ".....", ".....", "....."],
  "!": ["..#..", "..#..", "..#..", "..#..", "..#..", ".....", "..#.."],
  "'": ["..#..", "..#..", ".....", ".....", ".....", ".....", "....."],
  "(": ["...#.", "..#..", ".#...", ".#...", ".#...", "..#..", "...#."],
  ")": [".#...", "..#..", "...#.", "...#.", "...#.", "..#..", ".#..."],
  "*": ["..#..", "#.#.#", ".###.", "#.#.#", "..#..", ".....", "....."],
  "+": [".....", "..#..", "..#..", "#####", "..#..", "..#..", "....."],
  ",": [".....", ".....", ".....", ".....", ".##..", "..#..", ".#..."],
  "-": [".....", ".....", ".....", "#####", ".....", ".....", "....."],
  ".": [".....", ".....", ".....", ".....", ".....", ".##..", ".##.."],
  "/": ["....#", "....#", "...#.", "..#..", ".#...", "#....", "#...."],
  "0": [".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###."],
  "1": ["..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."],
  "2": [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"],
  "3": ["####.", "....#", "....#", ".###.", "....#", "....#", "####."],
  "4": ["...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."],
  "5": ["#####", "#....", "####.", "....#", "....#", "#...#", ".###."],
  "6": [".###.", "#....", "#....", "####.", "#...#", "#...#", ".###."],
  "7": ["#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."],
  "8": [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."],
  "9": [".###.", "#...#", "#...#", ".####", "....#", "....#", ".###."],
  ":": [".....", ".##..", ".##..", ".....", ".##..", ".##..", "....."],
  "<": ["...#.", "..#..", ".#...", "#....", ".#...", "..#..", "...#."],
  "=": [".....", ".....", "#####", ".....", "#####", ".....", "....."],
  ">": [".#...", "..#..", "...#.", "....#", "...#.", "..#..", ".#..."],
  "?": [".###.", "#...#", "....#", "...#.", "..#..", ".....", "..#.."],
  A: [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
  B: ["####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."],
  C: [".###.", "#...#", "#....", "#....", "#....", "#...#", ".###."],
  D: ["####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####."],
  E: ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
  F: ["#####", "#....", "#....", "####.", "#....", "#....", "#...."],
  G: [".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".###."],
  H: ["#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
  I: [".###.", "..#..", "..#..", "..#..", "..#..", "..#..", ".###."],
  J: ["..###", "...#.", "...#.", "...#.", "...#.", "#..#.", ".##.."],
  K: ["#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"],
  L: ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
  M: ["#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#"],
  N: ["#...#", "##..#", "##..#", "#.#.#", "#..##", "#..##", "#...#"],
  O: [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
  P: ["####.", "#...#", "#...#", "####.", "#....", "#....", "#...."],
  Q: [".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#"],
  R: ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
  S: [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
  T: ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
  U: ["#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
  V: ["#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#.."],
  W: ["#...#", "#...#", "#...#", "#.#.#", "#.#.#", "##.##", "#...#"],
  X: ["#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#"],
  Y: ["#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.."],
  Z: ["#####", "....#", "...#.", "..#..", ".#...", "#....", "#####"],
  _: [".....", ".....", ".....", ".....", ".....", ".....", "#####"],
};

function hex(value, width = 2) {
  return `$${(value >>> 0).toString(16).toUpperCase().padStart(width, "0")}`;
}

function glyphBytes(ch) {
  const rows = GLYPHS[ch] || GLYPHS[" "];
  const bytes = rows.map((row) => {
    if (row.length !== 5) throw new Error(`Glyph ${ch} has a bad row: ${row}`);
    let value = 0;
    for (let x = 0; x < 5; x += 1) if (row[x] === "#") value |= 0x40 >> x;
    return value;
  });
  bytes.push(0);
  return bytes;
}

function fontBlock() {
  const lines = [];
  // Codes 32..95 only; the rest of the 1K character page stays unused.
  lines.push(`CHARSET = ${hex(CHARSET_ORG, 4)}`);
  lines.push(`.ORG ${hex(CHARSET_ORG + 32 * 8, 4)}`);
  for (let code = 32; code < 96; code += 1) {
    const ch = String.fromCharCode(code);
    const bytes = glyphBytes(ch).map((value) => hex(value)).join(",");
    lines.push(`  .BYTE ${bytes}   ; ${ch === " " ? "space" : ch}`);
  }
  return lines;
}

function tablesBlock() {
  const cosine = [];
  for (let degrees = 0; degrees <= 90; degrees += 1) {
    cosine.push(Math.round(255 * Math.cos((degrees * Math.PI) / 180)));
  }
  const chord = [];
  for (let d = 0; d <= CRATER_RADIUS; d += 1) {
    chord.push(Math.round(Math.sqrt(CRATER_RADIUS * CRATER_RADIUS - d * d)));
  }
  const lines = [];
  lines.push(`CRATER_RADIUS = ${CRATER_RADIUS}`);
  lines.push("COS_TABLE:                       ; 255*cos(0..90 degrees)");
  for (let i = 0; i < cosine.length; i += 8) {
    lines.push(`  .BYTE ${cosine.slice(i, i + 8).map((v) => hex(v)).join(",")}`);
  }
  lines.push("CRATER_CHORD:                    ; half height of the crater per column offset");
  lines.push(`  .BYTE ${chord.map((v) => hex(v)).join(",")}`);
  return lines;
}

// Game display list: 8 blank lines, two HUD text rows (a DLI at the end of the
// second switches to the playfield palette), then 200 lines of ANTIC mode E.
// Two LMS addresses keep every 40-byte line inside a 4K page; a DLI every 16
// lines steps the sky/ground gradient.
function gameDisplayListBlock() {
  const rows = 200;
  const lines = [];
  lines.push("; ANTIC display lists must not cross a 1K boundary");
  lines.push(".ORG $4C00");
  lines.push("GAME_DL:");
  lines.push("  .BYTE $70");
  lines.push("  .BYTE $42");
  lines.push("  .WORD HUD_ROW0");
  lines.push("  .BYTE $82");
  for (let y = 0; y < rows; y += 1) {
    let op = 0x0e;
    if (y === 0 || y === 100) op |= 0x40;
    if (y > 0 && y % 16 === 0) op |= 0x80;
    lines.push(`  .BYTE ${hex(op)}`);
    if (y === 0) lines.push("  .WORD SCREEN_A");
    if (y === 100) lines.push("  .WORD SCREEN_B");
  }
  lines.push("  .BYTE $41");
  lines.push("  .WORD GAME_DL");
  return lines;
}

replaceBlock(targetPath, "GAME DISPLAY LIST", "node tools/generate_assets.js", gameDisplayListBlock());
replaceBlock(targetPath, "FONT", "node tools/generate_assets.js", fontBlock());
replaceBlock(targetPath, "TABLES", "node tools/generate_assets.js", tablesBlock());
console.log(`Updated ${path.relative(repoRoot, targetPath)}`);
