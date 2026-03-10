"use strict";

const fs = require("fs");
const path = require("path");
const vm = require("vm");
const { TextDecoder, TextEncoder } = require("util");

const repoRoot = path.resolve(__dirname, "..", "..");
const assemblerFiles = [
  "automation/A8E/jsA8E/js/core/cpu_tables.js",
  "automation/A8E/jsA8E/js/core/assembler/shared.js",
  "automation/A8E/jsA8E/js/core/assembler/lexer.js",
  "automation/A8E/jsA8E/js/core/assembler/preprocessor.js",
  "automation/A8E/jsA8E/js/core/assembler/parser.js",
  "automation/A8E/jsA8E/js/core/assembler/object_writer.js",
  "automation/A8E/jsA8E/js/core/assembler/assembler.js",
  "automation/A8E/jsA8E/js/core/assembler_core.js",
];

function createAssemblerContext() {
  const context = {
    ArrayBuffer,
    DataView,
    TextDecoder,
    TextEncoder,
    Uint8Array,
    clearTimeout,
    console,
    globalThis: null,
    self: null,
    setTimeout,
    window: null,
  };
  context.globalThis = context;
  context.self = context;
  context.window = context;
  vm.createContext(context);
  return context;
}

function loadAssemblerCore() {
  const context = createAssemblerContext();
  for (const relativeFile of assemblerFiles) {
    const absoluteFile = path.join(repoRoot, relativeFile);
    const sourceText = fs.readFileSync(absoluteFile, "utf8");
    vm.runInContext(sourceText, context, { filename: absoluteFile });
  }
  if (!context.A8EAssemblerCore) {
    throw new Error("Failed to load jsA8E assembler core.");
  }
  return context.A8EAssemblerCore;
}

function normalizeBytes(rawBytes) {
  if (!rawBytes) return Buffer.alloc(0);
  if (Buffer.isBuffer(rawBytes)) return rawBytes;
  if (ArrayBuffer.isView(rawBytes)) {
    return Buffer.from(rawBytes.buffer, rawBytes.byteOffset, rawBytes.byteLength);
  }
  if (rawBytes instanceof ArrayBuffer) return Buffer.from(rawBytes);
  if (Array.isArray(rawBytes)) return Buffer.from(rawBytes);
  if (typeof rawBytes.length === "number") return Buffer.from(Array.from(rawBytes));
  const values = Object.keys(rawBytes)
    .filter((key) => /^\d+$/.test(key))
    .sort((left, right) => Number(left) - Number(right))
    .map((key) => rawBytes[key] & 0xff);
  return Buffer.from(values);
}

function formatAssemblerFailure(result) {
  const lines = [];
  const errorText = result && result.error ? String(result.error) : "Assembly failed.";
  lines.push(errorText);
  if (result && Array.isArray(result.errors) && result.errors.length) {
    for (const entry of result.errors) {
      const lineNo =
        entry && entry.lineNo !== undefined && entry.lineNo !== null
          ? Number(entry.lineNo)
          : null;
      const prefix = Number.isFinite(lineNo) && lineNo > 0 ? `line ${lineNo}: ` : "";
      const message = entry && entry.message ? String(entry.message) : "Unknown error.";
      lines.push(`${prefix}${message}`);
    }
  }
  return lines.join("\n");
}

function assembleSourceText(sourceText, options) {
  const core = loadAssemblerCore();
  const buildOptions = Object.assign({}, options || {});
  const result = core.assembleToXex(String(sourceText), buildOptions);
  if (!result || !result.ok) {
    const details = formatAssemblerFailure(result || null);
    const error = new Error(details);
    error.result = result || null;
    throw error;
  }
  return {
    bytes: normalizeBytes(result.bytes),
    result: result,
  };
}

function assembleFile(sourcePath, options) {
  const absoluteSourcePath = path.resolve(sourcePath);
  const sourceText = fs.readFileSync(absoluteSourcePath, "utf8");
  const buildOptions = Object.assign({}, options || {});
  if (!buildOptions.sourceName) {
    buildOptions.sourceName = path.relative(repoRoot, absoluteSourcePath).replace(/\\/g, "/");
  }
  return assembleSourceText(sourceText, buildOptions);
}

module.exports = {
  assembleFile,
  assembleSourceText,
  formatAssemblerFailure,
  normalizeBytes,
  repoRoot,
};
