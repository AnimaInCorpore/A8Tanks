"use strict";

const fs = require("fs");
const http = require("http");
const path = require("path");

const mimeTypes = {
  ".asm": "text/plain; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".png": "image/png",
  ".rom": "application/octet-stream",
  ".svg": "image/svg+xml",
  ".txt": "text/plain; charset=utf-8",
  ".webp": "image/webp",
  ".xex": "application/octet-stream",
};

function sendResponse(response, statusCode, body, contentType) {
  response.writeHead(statusCode, {
    "Cache-Control": "no-store",
    "Content-Type": contentType,
  });
  response.end(body);
}

async function createStaticServer(options) {
  const rootDir = path.resolve(options.rootDir);
  const host = options.host || "127.0.0.1";
  const port = options.port || 0;

  const server = http.createServer((request, response) => {
    const requestUrl = new URL(request.url || "/", `http://${host}:${port}`);
    const decodedPath = decodeURIComponent(requestUrl.pathname);
    const absolutePath = path.resolve(rootDir, `.${decodedPath}`);

    if (!absolutePath.startsWith(rootDir)) {
      sendResponse(response, 403, "Forbidden\n", "text/plain; charset=utf-8");
      return;
    }

    let targetPath = absolutePath;
    try {
      const stats = fs.statSync(targetPath);
      if (stats.isDirectory()) targetPath = path.join(targetPath, "index.html");
    } catch {
      sendResponse(response, 404, "Not found\n", "text/plain; charset=utf-8");
      return;
    }

    let fileBuffer;
    try {
      fileBuffer = fs.readFileSync(targetPath);
    } catch {
      sendResponse(response, 404, "Not found\n", "text/plain; charset=utf-8");
      return;
    }

    const extension = path.extname(targetPath).toLowerCase();
    const contentType = mimeTypes[extension] || "application/octet-stream";
    response.writeHead(200, {
      "Cache-Control": "no-store",
      "Content-Length": fileBuffer.length,
      "Content-Type": contentType,
    });
    response.end(fileBuffer);
  });

  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(port, host, resolve);
  });

  const address = server.address();
  if (!address || typeof address === "string") {
    throw new Error("Unable to determine static server address.");
  }

  return {
    host: host,
    port: address.port,
    origin: `http://${host}:${address.port}`,
    close: () =>
      new Promise((resolve, reject) => {
        server.close((error) => {
          if (error) reject(error);
          else resolve();
        });
      }),
  };
}

module.exports = {
  createStaticServer,
};
