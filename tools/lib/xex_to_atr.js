"use strict";

const XEX_BOOT_LOADER = [
  0x00, 0x03, 0x00, 0x07, 0x07, 0x07, 0x60,
  0xa9, 0x00, 0x8d, 0xe0, 0x02, 0x8d, 0xe1, 0x02,
  0x8d, 0xe2, 0x02, 0x8d, 0xe3, 0x02, 0x85, 0x48,
  0xa9, 0x04, 0x85, 0x49, 0xa9, 0x00, 0x85, 0x4a,
  0x20, 0x7e, 0x07, 0xc9, 0xff, 0xd0, 0x4f,
  0x20, 0x7e, 0x07, 0xc9, 0xff, 0xd0, 0x48,
  0x20, 0x7e, 0x07, 0x85, 0x43,
  0x20, 0x7e, 0x07, 0x85, 0x44,
  0x20, 0x7e, 0x07, 0x85, 0x45,
  0x20, 0x7e, 0x07, 0x85, 0x46,
  0x20, 0x7e, 0x07, 0xa0, 0x00, 0x91, 0x43,
  0xe6, 0x43, 0xd0, 0x02, 0xe6, 0x44,
  0xa5, 0x44, 0xc5, 0x46, 0x90, 0xed, 0xd0, 0x06,
  0xa5, 0x45, 0xc5, 0x43, 0xb0, 0xe5,
  0xad, 0xe3, 0x02, 0xf0, 0xbe,
  0xa9, 0x07, 0x48, 0xa9, 0x69, 0x48, 0x6c, 0xe2, 0x02,
  0xa9, 0x00, 0x8d, 0xe2, 0x02, 0x8d, 0xe3, 0x02,
  0x4c, 0x1f, 0x07,
  0xad, 0xe1, 0x02, 0xf0, 0x03, 0x6c, 0xe0, 0x02,
  0x60,
  0xa5, 0x48, 0xd0, 0x03, 0x20, 0x8f, 0x07,
  0xa6, 0x47, 0xbd, 0x00, 0x06, 0xe6, 0x47, 0xc6, 0x48, 0x60,
  0xa9, 0x31, 0x8d, 0x00, 0x03,
  0xa9, 0x01, 0x8d, 0x01, 0x03,
  0xa9, 0x52, 0x8d, 0x02, 0x03,
  0xa9, 0x40, 0x8d, 0x03, 0x03,
  0xa9, 0x00, 0x8d, 0x04, 0x03,
  0xa9, 0x06, 0x8d, 0x05, 0x03,
  0xa9, 0x07, 0x8d, 0x06, 0x03,
  0xa9, 0x80, 0x8d, 0x08, 0x03,
  0xa9, 0x00, 0x8d, 0x09, 0x03,
  0xa5, 0x49, 0x8d, 0x0a, 0x03,
  0xa5, 0x4a, 0x8d, 0x0b, 0x03,
  0x20, 0x59, 0xe4,
  0xe6, 0x49, 0xd0, 0x02, 0xe6, 0x4a,
  0xa9, 0x00, 0x85, 0x47,
  0xa9, 0x80, 0x85, 0x48,
  0x60,
];

const XEX_BOOT_LOADER_BASE = 0x0700;
const XEX_BOOT_PATCH_GETBYTE_BUF_LO = 0x0788 - XEX_BOOT_LOADER_BASE;
const XEX_BOOT_PATCH_GETBYTE_BUF_HI = 0x0789 - XEX_BOOT_LOADER_BASE;
const XEX_BOOT_PATCH_DBUF_LO = 0x07a4 - XEX_BOOT_LOADER_BASE;
const XEX_BOOT_PATCH_DBUF_HI = 0x07a9 - XEX_BOOT_LOADER_BASE;
const XEX_BOOT_LOADER_RESERVED_START = 0x0700;
const XEX_BOOT_LOADER_RESERVED_END = 0x087f;
const XEX_SEGMENT_MARKER = 0xff;

const ATR_HEADER_SIZE = 16;
const ATR_SECTOR_SIZE = 128;
const ATR_BOOT_SECTOR_COUNT = 3;
const ATR_BOOT_LOADER_SIZE = ATR_BOOT_SECTOR_COUNT * ATR_SECTOR_SIZE;
const ATR_DATA_OFFSET = ATR_HEADER_SIZE + ATR_BOOT_LOADER_SIZE;

function normalizeInputBytes(input) {
  if (!input) return new Uint8Array(0);
  if (input instanceof Uint8Array) return input;
  if (Buffer.isBuffer(input)) return new Uint8Array(input.buffer, input.byteOffset, input.byteLength);
  if (ArrayBuffer.isView(input)) {
    return new Uint8Array(input.buffer, input.byteOffset, input.byteLength);
  }
  if (input instanceof ArrayBuffer) return new Uint8Array(input);
  if (Array.isArray(input)) return Uint8Array.from(input);
  if (typeof input.length === "number") return Uint8Array.from(Array.from(input));
  return new Uint8Array(0);
}

function skipXexSegmentMarkers(bytes, startIndex) {
  let index = startIndex | 0;
  while (
    index + 1 < bytes.length &&
    bytes[index] === XEX_SEGMENT_MARKER &&
    bytes[index + 1] === XEX_SEGMENT_MARKER
  ) {
    index += 2;
  }
  return index;
}

function normalizeXex(xexBytes) {
  let index = 0;
  let total = 0;
  let foundSegment = false;

  while (index < xexBytes.length) {
    index = skipXexSegmentMarkers(xexBytes, index);
    if (index >= xexBytes.length || index + 3 >= xexBytes.length) break;

    const start = (xexBytes[index] & 0xff) | ((xexBytes[index + 1] & 0xff) << 8);
    const end = (xexBytes[index + 2] & 0xff) | ((xexBytes[index + 3] & 0xff) << 8);
    if (end < start) return null;

    const segmentSize = end - start + 1;
    index += 4;
    if (index + segmentSize > xexBytes.length) return null;

    total += 6 + segmentSize;
    index += segmentSize;
    foundSegment = true;
  }

  if (!foundSegment) return null;

  const normalized = new Uint8Array(total);
  let out = 0;
  index = 0;

  while (index < xexBytes.length) {
    index = skipXexSegmentMarkers(xexBytes, index);
    if (index >= xexBytes.length || index + 3 >= xexBytes.length) break;

    const startLo = xexBytes[index] & 0xff;
    const startHi = xexBytes[index + 1] & 0xff;
    const endLo = xexBytes[index + 2] & 0xff;
    const endHi = xexBytes[index + 3] & 0xff;
    const start = startLo | (startHi << 8);
    const end = endLo | (endHi << 8);
    if (end < start) return null;

    const segmentSize = end - start + 1;
    index += 4;
    if (index + segmentSize > xexBytes.length) return null;

    normalized[out++] = XEX_SEGMENT_MARKER;
    normalized[out++] = XEX_SEGMENT_MARKER;
    normalized[out++] = startLo;
    normalized[out++] = startHi;
    normalized[out++] = endLo;
    normalized[out++] = endHi;
    normalized.set(xexBytes.subarray(index, index + segmentSize), out);
    out += segmentSize;
    index += segmentSize;
  }

  return out === normalized.length ? normalized : null;
}

function xexSegmentOverlapsRange(normalizedXex, rangeStart, rangeEnd) {
  let index = 0;

  while (index + 5 < normalizedXex.length) {
    if (
      normalizedXex[index] !== XEX_SEGMENT_MARKER ||
      normalizedXex[index + 1] !== XEX_SEGMENT_MARKER
    ) {
      return true;
    }

    const start = (normalizedXex[index + 2] & 0xff) | ((normalizedXex[index + 3] & 0xff) << 8);
    const end = (normalizedXex[index + 4] & 0xff) | ((normalizedXex[index + 5] & 0xff) << 8);
    if (end < start) return true;
    const segmentSize = end - start + 1;

    if (!(end < rangeStart || start > rangeEnd)) return true;
    if (index + 6 + segmentSize > normalizedXex.length) return true;

    index += 6 + segmentSize;
  }

  return false;
}

function chooseXexBootBuffer(normalizedXex) {
  if (!xexSegmentOverlapsRange(normalizedXex, 0x0600, 0x067f)) return 0x0600;

  for (let candidate = 0x0880; candidate <= 0x4f80; candidate += 0x80) {
    if (!xexSegmentOverlapsRange(normalizedXex, candidate, candidate + 0x7f)) {
      return candidate;
    }
  }

  for (let candidate = 0x5800; candidate <= 0x9f80; candidate += 0x80) {
    if (!xexSegmentOverlapsRange(normalizedXex, candidate, candidate + 0x7f)) {
      return candidate;
    }
  }

  return -1;
}

function buildXexBootLoader(normalizedXex) {
  if (
    xexSegmentOverlapsRange(
      normalizedXex,
      XEX_BOOT_LOADER_RESERVED_START,
      XEX_BOOT_LOADER_RESERVED_END,
    )
  ) {
    return null;
  }

  const bufferAddr = chooseXexBootBuffer(normalizedXex);
  if (bufferAddr < 0) return null;

  const loader = XEX_BOOT_LOADER.slice();
  loader[XEX_BOOT_PATCH_GETBYTE_BUF_LO] = bufferAddr & 0xff;
  loader[XEX_BOOT_PATCH_GETBYTE_BUF_HI] = (bufferAddr >> 8) & 0xff;
  loader[XEX_BOOT_PATCH_DBUF_LO] = bufferAddr & 0xff;
  loader[XEX_BOOT_PATCH_DBUF_HI] = (bufferAddr >> 8) & 0xff;
  return loader;
}

function convertXexToAtr(xexBytes) {
  const bytes = normalizeInputBytes(xexBytes);
  const normalizedXex = normalizeXex(bytes);
  if (!normalizedXex) return null;

  const bootLoader = buildXexBootLoader(normalizedXex);
  if (!bootLoader) return null;

  const dataSectors = Math.ceil(normalizedXex.length / ATR_SECTOR_SIZE);
  const totalSize = ATR_HEADER_SIZE + ATR_BOOT_LOADER_SIZE + dataSectors * ATR_SECTOR_SIZE;
  const paragraphs = (totalSize - ATR_HEADER_SIZE) >> 4;
  const atr = new Uint8Array(totalSize);

  atr[0] = 0x96;
  atr[1] = 0x02;
  atr[2] = paragraphs & 0xff;
  atr[3] = (paragraphs >> 8) & 0xff;
  atr[4] = ATR_SECTOR_SIZE;
  atr[5] = 0x00;
  atr[6] = (paragraphs >> 16) & 0xff;
  atr[7] = (paragraphs >> 24) & 0xff;

  for (let index = 0; index < bootLoader.length; index += 1) {
    atr[ATR_HEADER_SIZE + index] = bootLoader[index];
  }

  atr.set(normalizedXex, ATR_DATA_OFFSET);
  return Buffer.from(atr.buffer, atr.byteOffset, atr.byteLength);
}

module.exports = {
  convertXexToAtr,
};
