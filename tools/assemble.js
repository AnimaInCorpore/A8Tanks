#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");

const { assembleFile, repoRoot } = require("./lib/jsa8e_assembler");
const { convertXexToAtr } = require("./lib/xex_to_atr");

function printHelp() {
  console.log(`Usage: node tools/assemble.js [options]

Options:
  --source <path>   Assembly source file to build
  --output <path>   Output XEX path
  --atr-output <path>  Output ATR path (default: sibling of XEX output)
  --help            Show this help
`);
}

function parseArgs(argv) {
  const options = {};
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--help") {
      options.help = true;
      continue;
    }
    if (arg === "--source") {
      options.source = argv[index + 1];
      index += 1;
      continue;
    }
    if (arg === "--output") {
      options.output = argv[index + 1];
      index += 1;
      continue;
    }
    if (arg === "--atr-output") {
      options.atrOutput = argv[index + 1];
      index += 1;
      continue;
    }
    throw new Error(`Unknown argument: ${arg}`);
  }
  return options;
}

function resolveFromRepo(inputPath) {
  return path.resolve(repoRoot, inputPath);
}

function defaultAtrOutputFor(xexOutputPath) {
  return path.join(
    path.dirname(xexOutputPath),
    `${path.basename(xexOutputPath, path.extname(xexOutputPath))}.atr`,
  );
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    printHelp();
    return;
  }

  const sourcePath = resolveFromRepo(options.source || "src/a8tanks.asm");
  const defaultOutput = `build/${path.basename(sourcePath, path.extname(sourcePath))}.xex`;
  const outputPath = resolveFromRepo(options.output || defaultOutput);
  const atrOutputPath = resolveFromRepo(
    options.atrOutput || defaultAtrOutputFor(outputPath),
  );
  const assembled = assembleFile(sourcePath);
  const atrBytes = convertXexToAtr(assembled.bytes);

  if (!atrBytes) {
    throw new Error("Unable to convert assembled XEX into a bootable ATR.");
  }

  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  fs.writeFileSync(outputPath, assembled.bytes);
  fs.mkdirSync(path.dirname(atrOutputPath), { recursive: true });
  fs.writeFileSync(atrOutputPath, atrBytes);

  const build = assembled.result;
  const runAddr =
    build && typeof build.runAddr === "number"
      ? `$${build.runAddr.toString(16).toUpperCase().padStart(4, "0")}`
      : "n/a";

  console.log(`Source : ${path.relative(repoRoot, sourcePath)}`);
  console.log(`Output : ${path.relative(repoRoot, outputPath)}`);
  console.log(`ATR    : ${path.relative(repoRoot, atrOutputPath)}`);
  console.log(`Bytes  : ${assembled.bytes.length}`);
  console.log(`Run    : ${runAddr}`);
}

try {
  main();
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
}
