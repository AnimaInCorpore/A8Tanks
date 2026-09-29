#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const repoRoot = path.resolve(__dirname, "..");
const sourceImage = path.resolve(repoRoot, process.argv[2] || "build/a8tanks-ref.png");
const outputPath = path.resolve(repoRoot, process.argv[3] || "src/a8tanks.asm");

const { replaceBlock } = require("./lib/asm_blocks");

const WIDTH = 160;
const SOURCE_HEIGHT = 224;
// The bottom of the reference image only holds border artifacts; the game
// replaces it with a one-line text row (mode select / prompt).
const HEIGHT = 208;
const BYTES_PER_ROW = WIDTH / 4;
const DISPLAY_LIST_ORG = 0x8000;
const BITMAP_ORG = 0x8400;
const TABLE_ORG = 0xa800;

function hex(value, width = 2) {
  return `$${(value >>> 0).toString(16).toUpperCase().padStart(width, "0")}`;
}

function runMagickPpm(inputPath) {
  const magick = process.env.MAGICK || "magick";
  const result = spawnSync(
    magick,
    [inputPath, "-resize", `${WIDTH}x${SOURCE_HEIGHT}!`, "ppm:-"],
    { encoding: null, maxBuffer: 32 * 1024 * 1024 },
  );
  if (result.status !== 0) {
    const stderr = result.stderr ? result.stderr.toString("utf8") : "";
    throw new Error(`ImageMagick failed:\n${stderr}`);
  }
  return result.stdout;
}

function parsePpm(buffer) {
  let index = 0;
  function skipWhitespaceAndComments() {
    while (index < buffer.length) {
      const char = buffer[index];
      if (char === 35) {
        while (index < buffer.length && buffer[index] !== 10) index += 1;
        continue;
      }
      if (char === 9 || char === 10 || char === 13 || char === 32) {
        index += 1;
        continue;
      }
      break;
    }
  }
  function readToken() {
    skipWhitespaceAndComments();
    const start = index;
    while (index < buffer.length) {
      const char = buffer[index];
      if (char === 9 || char === 10 || char === 13 || char === 32 || char === 35) break;
      index += 1;
    }
    return buffer.subarray(start, index).toString("ascii");
  }

  const magic = readToken();
  const width = Number(readToken());
  const height = Number(readToken());
  const max = Number(readToken());
  if (magic !== "P6" || width !== WIDTH || height !== SOURCE_HEIGHT || max !== 255) {
    throw new Error(`Unexpected PPM header: ${magic} ${width}x${height} max ${max}`);
  }
  if (buffer[index] === 9 || buffer[index] === 10 || buffer[index] === 13 || buffer[index] === 32) {
    index += 1;
  }
  const expectedLength = WIDTH * SOURCE_HEIGHT * 3;
  const data = buffer.subarray(index, index + expectedLength);
  if (data.length !== expectedLength) {
    throw new Error(`Unexpected PPM payload length: ${data.length}`);
  }
  return data;
}

function createAtariPalette() {
  const clamp = (value) => Math.max(0, Math.min(255, value | 0));
  const hueAngle = [
    0.0, 163.0, 150.0, 109.0, 42.0, 17.0, -3.0, -14.0,
    -26.0, -53.0, -80.0, -107.0, -134.0, -161.0, -188.0, -197.0,
  ];
  const palette = [];
  for (let lum = 0; lum < 16; lum += 1) {
    for (let hue = 0; hue < 16; hue += 1) {
      let dS;
      let dY;
      if (hue === 0) {
        dS = 0.0;
        dY = lum / 15.0;
      } else {
        dS = 0.5;
        dY = (lum + 0.9) / 15.9;
      }
      const angle = (hueAngle[hue] / 180.0) * Math.PI;
      const dR = dY + dS * Math.sin(angle);
      const dG = dY - (27.0 / 53.0) * dS * Math.sin(angle) - (10.0 / 53.0) * dS * Math.cos(angle);
      const dB = dY + dS * Math.cos(angle);
      const code = (hue << 4) | lum;
      palette.push({
        code,
        r: clamp(dR * 256.0),
        g: clamp(dG * 256.0),
        b: clamp(dB * 256.0),
      });
    }
  }
  return palette;
}

const atariPalette = createAtariPalette();

function distanceSquared(a, b) {
  const dr = a.r - b.r;
  const dg = a.g - b.g;
  const db = a.b - b.b;
  return dr * dr + dg * dg + db * db;
}

function nearestAtariColor(color) {
  let best = atariPalette[0];
  let bestDistance = Infinity;
  for (const candidate of atariPalette) {
    const distance = distanceSquared(color, candidate);
    if (distance < bestDistance) {
      best = candidate;
      bestDistance = distance;
    }
  }
  return best;
}

function medianCutCentroids(pixels) {
  let boxes = [pixels.slice()];
  while (boxes.length < 4) {
    let bestIndex = -1;
    let bestScore = -1;
    for (let index = 0; index < boxes.length; index += 1) {
      const box = boxes[index];
      if (box.length < 2) continue;
      const bounds = getBounds(box);
      const range = Math.max(bounds.maxR - bounds.minR, bounds.maxG - bounds.minG, bounds.maxB - bounds.minB);
      const score = range * Math.sqrt(box.length);
      if (score > bestScore) {
        bestScore = score;
        bestIndex = index;
      }
    }
    if (bestIndex < 0) break;
    const box = boxes.splice(bestIndex, 1)[0];
    const bounds = getBounds(box);
    const ranges = [
      { key: "r", value: bounds.maxR - bounds.minR },
      { key: "g", value: bounds.maxG - bounds.minG },
      { key: "b", value: bounds.maxB - bounds.minB },
    ].sort((left, right) => right.value - left.value);
    const channel = ranges[0].key;
    box.sort((left, right) => left[channel] - right[channel]);
    const middle = Math.max(1, Math.floor(box.length / 2));
    boxes.push(box.slice(0, middle), box.slice(middle));
  }
  while (boxes.length < 4) boxes.push([pixels[0]]);
  return boxes.slice(0, 4).map(meanColor);
}

function getBounds(pixels) {
  const bounds = {
    minR: 255, minG: 255, minB: 255,
    maxR: 0, maxG: 0, maxB: 0,
  };
  for (const pixel of pixels) {
    if (pixel.r < bounds.minR) bounds.minR = pixel.r;
    if (pixel.g < bounds.minG) bounds.minG = pixel.g;
    if (pixel.b < bounds.minB) bounds.minB = pixel.b;
    if (pixel.r > bounds.maxR) bounds.maxR = pixel.r;
    if (pixel.g > bounds.maxG) bounds.maxG = pixel.g;
    if (pixel.b > bounds.maxB) bounds.maxB = pixel.b;
  }
  return bounds;
}

function meanColor(pixels) {
  let r = 0;
  let g = 0;
  let b = 0;
  for (const pixel of pixels) {
    r += pixel.r;
    g += pixel.g;
    b += pixel.b;
  }
  const count = Math.max(1, pixels.length);
  return { r: r / count, g: g / count, b: b / count };
}

function rowPalette(rowPixels) {
  let centroids = medianCutCentroids(rowPixels);
  for (let iteration = 0; iteration < 6; iteration += 1) {
    const buckets = centroids.map(() => []);
    for (const pixel of rowPixels) {
      let bestIndex = 0;
      let bestDistance = Infinity;
      for (let index = 0; index < centroids.length; index += 1) {
        const distance = distanceSquared(pixel, centroids[index]);
        if (distance < bestDistance) {
          bestIndex = index;
          bestDistance = distance;
        }
      }
      buckets[bestIndex].push(pixel);
    }
    centroids = buckets.map((bucket, index) => (bucket.length ? meanColor(bucket) : centroids[index]));
  }

  const chosen = [];
  for (const centroid of centroids) {
    const color = nearestAtariColor(centroid);
    if (!chosen.some((entry) => entry.code === color.code)) chosen.push(color);
  }
  while (chosen.length < 4) {
    let best = atariPalette[0];
    let bestDistance = -1;
    for (const pixel of rowPixels) {
      for (const candidate of atariPalette) {
        if (chosen.some((entry) => entry.code === candidate.code)) continue;
        const nearestChosen = Math.min(...chosen.map((entry) => distanceSquared(pixel, entry)));
        const distance = Math.min(nearestChosen, distanceSquared(pixel, candidate));
        if (distance > bestDistance) {
          best = candidate;
          bestDistance = distance;
        }
      }
    }
    chosen.push(best);
  }

  const usage = new Array(chosen.length).fill(0);
  for (const pixel of rowPixels) {
    usage[nearestColorIndex(pixel, chosen)] += 1;
  }
  const ordered = chosen
    .map((color, index) => ({ color, count: usage[index] }))
    .sort((left, right) => right.count - left.count)
    .map((entry) => entry.color);
  return ordered.slice(0, 4);
}

function nearestColorIndex(pixel, colors) {
  let bestIndex = 0;
  let bestDistance = Infinity;
  for (let index = 0; index < colors.length; index += 1) {
    const distance = distanceSquared(pixel, colors[index]);
    if (distance < bestDistance) {
      bestIndex = index;
      bestDistance = distance;
    }
  }
  return bestIndex;
}

function encodeImage(ppmData) {
  const bitmapRows = [];
  const colbk = [];
  const pf0 = [];
  const pf1 = [];
  const pf2 = [];

  for (let y = 0; y < HEIGHT; y += 1) {
    const rowPixels = [];
    for (let x = 0; x < WIDTH; x += 1) {
      const offset = (y * WIDTH + x) * 3;
      rowPixels.push({
        r: ppmData[offset],
        g: ppmData[offset + 1],
        b: ppmData[offset + 2],
      });
    }
    const colors = rowPalette(rowPixels);
    colbk.push(colors[0].code);
    pf0.push(colors[1].code);
    pf1.push(colors[2].code);
    pf2.push(colors[3].code);

    const rowBytes = [];
    for (let xByte = 0; xByte < BYTES_PER_ROW; xByte += 1) {
      let value = 0;
      for (let pixel = 0; pixel < 4; pixel += 1) {
        const x = xByte * 4 + pixel;
        const index = nearestColorIndex(rowPixels[x], colors);
        value |= (index & 0x03) << (6 - pixel * 2);
      }
      rowBytes.push(value);
    }
    bitmapRows.push(rowBytes);
  }

  return { bitmapRows, colbk, pf0, pf1, pf2 };
}

function byteLine(bytes) {
  return `  .BYTE ${bytes.map((value) => hex(value)).join(",")}`;
}

// The title screen is a mode E bitmap whose per-scanline palette is applied by
// the title DLI in src/a8tanks.asm.  Everything data-like is emitted here:
// display list, bitmap and the four per-scanline colour tables.
function generateTitleBlock(encoded) {
  const lines = [];
  lines.push(`TITLE_ROWS = ${hex(HEIGHT)}`);
  lines.push(`TITLE_COLBK0 = ${hex(encoded.colbk[0])}`);
  lines.push(`TITLE_PF0_0 = ${hex(encoded.pf0[0])}`);
  lines.push(`TITLE_PF1_0 = ${hex(encoded.pf1[0])}`);
  lines.push(`TITLE_PF2_0 = ${hex(encoded.pf2[0])}`);
  lines.push("");
  lines.push(`.ORG ${hex(DISPLAY_LIST_ORG, 4)}`);
  lines.push("");
  lines.push("TITLE_DISPLAY_LIST:");
  lines.push("  .BYTE $F0              ; 8 blank scanlines, DLI sets bitmap palettes");
  for (let y = 0; y < HEIGHT; y += 1) {
    lines.push("  .BYTE $4E");
    lines.push(`  .WORD TITLE_BITMAP+${hex(y * BYTES_PER_ROW, 4)}`);
  }
  lines.push("  .BYTE $42              ; mode 2 text row for the mode select prompt");
  lines.push("  .WORD TITLE_TEXT");
  lines.push("  .BYTE $41");
  lines.push("  .WORD TITLE_DISPLAY_LIST");
  lines.push("");
  lines.push(`.ORG ${hex(BITMAP_ORG, 4)}`);
  lines.push("");
  lines.push("TITLE_BITMAP:");
  for (const row of encoded.bitmapRows) lines.push(byteLine(row));
  lines.push("");
  lines.push(`.ORG ${hex(TABLE_ORG, 4)}`);
  lines.push("");
  lines.push("TITLE_COLBK:");
  for (let y = 0; y < HEIGHT; y += 8) lines.push(byteLine(encoded.colbk.slice(y, y + 8)));
  lines.push("TITLE_PF0:");
  for (let y = 0; y < HEIGHT; y += 8) lines.push(byteLine(encoded.pf0.slice(y, y + 8)));
  lines.push("TITLE_PF1:");
  for (let y = 0; y < HEIGHT; y += 8) lines.push(byteLine(encoded.pf1.slice(y, y + 8)));
  lines.push("TITLE_PF2:");
  for (let y = 0; y < HEIGHT; y += 8) lines.push(byteLine(encoded.pf2.slice(y, y + 8)));
  return lines;
}

function writeTitleBlock(encoded, targetPath) {
  replaceBlock(targetPath, "TITLE SCREEN", "node tools/generate_start_screen.js", generateTitleBlock(encoded));
}

module.exports = { generateTitleBlock, writeTitleBlock, HEIGHT };

if (require.main === module) {
  if (!fs.existsSync(sourceImage)) {
    throw new Error(`Source image not found: ${sourceImage}`);
  }

  const ppm = parsePpm(runMagickPpm(sourceImage));
  const encoded = encodeImage(ppm);
  writeTitleBlock(encoded, outputPath);
  console.log(`Updated ${path.relative(repoRoot, outputPath)} from ${path.relative(repoRoot, sourceImage)}`);
}
