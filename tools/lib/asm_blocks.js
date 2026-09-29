"use strict";

const fs = require("fs");

// Generated data lives inside the hand-written source between marker lines:
//   ; >>> GENERATED <name> ...
//   ; <<< GENERATED <name>
// so the whole game stays a single assembly file.

function markers(name) {
  return {
    begin: new RegExp(`^; >>> GENERATED ${name}\\b.*$`, "m"),
    end: new RegExp(`^; <<< GENERATED ${name}\\s*$`, "m"),
  };
}

function blockText(name, comment, bodyLines) {
  return [
    `; >>> GENERATED ${name} (${comment})`,
    ...bodyLines,
    `; <<< GENERATED ${name}`,
  ].join("\n");
}

function replaceBlock(filePath, name, comment, bodyLines) {
  const source = fs.readFileSync(filePath, "utf8");
  const { begin, end } = markers(name);
  const beginMatch = begin.exec(source);
  const endMatch = end.exec(source);
  if (!beginMatch || !endMatch || endMatch.index < beginMatch.index) {
    throw new Error(`${filePath}: missing GENERATED ${name} block markers`);
  }
  const before = source.slice(0, beginMatch.index);
  const after = source.slice(endMatch.index + endMatch[0].length);
  fs.writeFileSync(filePath, before + blockText(name, comment, bodyLines) + after);
}

module.exports = { replaceBlock, blockText };
