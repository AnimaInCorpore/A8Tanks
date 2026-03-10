#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");

const { createStaticServer } = require("./lib/static_server");
const { repoRoot } = require("./lib/jsa8e_assembler");

function printHelp() {
  console.log(`Usage: node tools/run.js [options]

Options:
  --source <path>      Assembly source file to assemble and run
  --os-rom <path>      Path to ATARIXL.ROM
  --basic-rom <path>   Path to ATARIBAS.ROM
  --port <number>      Static server port (default: random free port)
  --show               Launch Chromium with a visible window
  --timeout-ms <ms>    Breakpoint wait timeout (default: 5000)
  --xex-output <path>  Where to write the assembled XEX
  --screenshot <path>  Where to write the captured PNG
  --artifacts <path>   Where to write the JSON run artifacts
  --help               Show this help
`);
}

function parseArgs(argv) {
  const options = {
    headless: true,
    timeoutMs: 5000,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--help") {
      options.help = true;
      continue;
    }
    if (arg === "--show") {
      options.headless = false;
      continue;
    }
    if (arg === "--source") {
      options.source = argv[index + 1];
      index += 1;
      continue;
    }
    if (arg === "--os-rom") {
      options.osRom = argv[index + 1];
      index += 1;
      continue;
    }
    if (arg === "--basic-rom") {
      options.basicRom = argv[index + 1];
      index += 1;
      continue;
    }
    if (arg === "--port") {
      options.port = Number(argv[index + 1]);
      index += 1;
      continue;
    }
    if (arg === "--timeout-ms") {
      options.timeoutMs = Number(argv[index + 1]);
      index += 1;
      continue;
    }
    if (arg === "--xex-output") {
      options.xexOutput = argv[index + 1];
      index += 1;
      continue;
    }
    if (arg === "--screenshot") {
      options.screenshot = argv[index + 1];
      index += 1;
      continue;
    }
    if (arg === "--artifacts") {
      options.artifacts = argv[index + 1];
      index += 1;
      continue;
    }
    throw new Error(`Unknown argument: ${arg}`);
  }

  return options;
}

function requirePlaywright() {
  try {
    return require("playwright");
  } catch (firstError) {
    try {
      return require("playwright-core");
    } catch {
      throw new Error(
        "Playwright is required to run jsA8E. Install dependencies with `npm install` first.",
      );
    }
  }
}

function resolveRepoPath(inputPath) {
  return path.resolve(repoRoot, inputPath);
}

function resolveRomPath(kind, explicitPath, envVarName, fallbacks) {
  const candidates = [];
  if (explicitPath) candidates.push(path.resolve(explicitPath));
  if (process.env[envVarName]) candidates.push(path.resolve(process.env[envVarName]));
  for (const fallback of fallbacks) candidates.push(resolveRepoPath(fallback));

  for (const candidate of candidates) {
    if (candidate && fs.existsSync(candidate)) return candidate;
  }

  throw new Error(
    `Unable to locate the ${kind} ROM. Pass --${kind}-rom <path> or set ${envVarName}.`,
  );
}

function ensureParentDir(filePath) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
}

function writeJson(filePath, value) {
  ensureParentDir(filePath);
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`);
}

async function runInBrowser(options) {
  const { chromium } = requirePlaywright();
  const sourcePath = resolveRepoPath(options.source || "src/a8tanks.asm");
  const sourceName = path.relative(repoRoot, sourcePath).replace(/\\/g, "/");
  const sourceText = fs.readFileSync(sourcePath, "utf8");

  const baseName = path.basename(sourcePath, path.extname(sourcePath));
  const xexOutput = resolveRepoPath(options.xexOutput || `build/${baseName}.xex`);
  const screenshotPath = resolveRepoPath(options.screenshot || `build/${baseName}.png`);
  const artifactsPath = resolveRepoPath(options.artifacts || `build/${baseName}-run.json`);

  const osRomPath = resolveRomPath("os", options.osRom, "A8TANKS_OS_ROM", [
    "ATARIXL.ROM",
    "automation/A8E/ATARIXL.ROM",
  ]);
  const basicRomPath = resolveRomPath("basic", options.basicRom, "A8TANKS_BASIC_ROM", [
    "ATARIBAS.ROM",
    "automation/A8E/ATARIBAS.ROM",
  ]);

  const server = await createStaticServer({
    rootDir: repoRoot,
    port: Number.isFinite(options.port) ? options.port : 0,
  });

  let browser;
  try {
    browser = await chromium.launch({ headless: options.headless });
    const page = await browser.newPage({
      viewport: { width: 1280, height: 960 },
    });

    page.on("pageerror", (error) => {
      console.error(`jsA8E page error: ${error.message}`);
    });

    await page.goto(`${server.origin}/automation/A8E/jsA8E/`, {
      // jsA8E loads third-party fonts/assets that can keep the page "busy"
      // longer than the automation API actually needs to become ready.
      waitUntil: "domcontentloaded",
      timeout: Math.max(options.timeoutMs * 2, 10000),
    });
    await page.waitForFunction(
      () => !!(window.A8EAutomation && typeof window.A8EAutomation.whenReady === "function"),
      { timeout: Math.max(options.timeoutMs, 5000) },
    );

    const osBase64 = fs.readFileSync(osRomPath).toString("base64");
    const basicBase64 = fs.readFileSync(basicRomPath).toString("base64");

    const result = await page.evaluate(
      async ({ osBase64, basicBase64, sourceName, sourceText, timeoutMs }) => {
        const api = await window.A8EAutomation.whenReady();
        const capabilities = await api.getCapabilities();

        await api.media.loadRom("os", { base64: osBase64 });
        await api.media.loadRom("basic", { base64: basicBase64 });

        const build = await api.dev.assembleSource({
          name: sourceName,
          text: sourceText,
        });

        if (!build || !build.ok) {
          return {
            ok: false,
            stage: "assemble",
            build: build,
          };
        }

        const entryPoint = typeof build.runAddr === "number" ? build.runAddr : 0x2000;
        await api.debug.setBreakpoints([entryPoint]);

        const run = await api.dev.runXex({
          build: build,
          saveHostFile: true,
        });

        const stop = await api.debug.waitForBreakpoint({ timeoutMs: timeoutMs });
        const debugState = await api.debug.getDebugState();
        const sourceContext = await api.debug.getSourceContext({
          pc: debugState ? debugState.pc : entryPoint,
          beforeLines: 4,
          afterLines: 4,
        });
        const disassembly = await api.debug.disassemble({
          pc: debugState ? debugState.pc : entryPoint,
          beforeInstructions: 6,
          afterInstructions: 6,
        });
        const screenshot = await api.artifacts.captureScreenshot();
        const systemState = await api.getSystemState();

        return {
          ok: true,
          build: build,
          capabilities: capabilities,
          debugState: debugState,
          disassembly: disassembly,
          run: run,
          screenshot: screenshot,
          sourceContext: sourceContext,
          stop: stop,
          systemState: systemState,
        };
      },
      {
        basicBase64: basicBase64,
        osBase64: osBase64,
        sourceName: sourceName,
        sourceText: sourceText,
        timeoutMs: options.timeoutMs,
      },
    );

    if (!result || !result.ok) {
      const build = result && result.build ? result.build : null;
      let message = "jsA8E automation run failed.";
      if (build && build.error) message = build.error;
      if (build && Array.isArray(build.errors) && build.errors.length) {
        message += `\n${build.errors.map((entry) => {
          const lineNo =
            entry && entry.lineNo !== undefined && entry.lineNo !== null
              ? `line ${entry.lineNo}: `
              : "";
          return `${lineNo}${entry.message || "Unknown error."}`;
        }).join("\n")}`;
      }
      throw new Error(message);
    }

    ensureParentDir(xexOutput);
    fs.writeFileSync(xexOutput, Buffer.from(result.build.bytes));

    ensureParentDir(screenshotPath);
    fs.writeFileSync(screenshotPath, Buffer.from(result.screenshot.base64, "base64"));

    writeJson(artifactsPath, {
      build: {
        byteLength: result.build.byteLength,
        runAddr: result.build.runAddr,
        sourceName: result.build.sourceName,
        symbols: result.build.symbols,
      },
      capabilities: result.capabilities,
      debugState: result.debugState,
      disassembly: result.disassembly,
      roms: {
        basic: path.relative(repoRoot, basicRomPath),
        os: path.relative(repoRoot, osRomPath),
      },
      run: result.run,
      sourceContext: result.sourceContext,
      stop: result.stop,
      systemState: result.systemState,
    });

    return {
      artifactsPath: artifactsPath,
      runAddr: result.build.runAddr,
      screenshotPath: screenshotPath,
      sourcePath: sourcePath,
      xexOutput: xexOutput,
    };
  } finally {
    if (browser) await browser.close();
    await server.close();
  }
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    printHelp();
    return;
  }

  const summary = await runInBrowser(options);
  const runAddr =
    typeof summary.runAddr === "number"
      ? `$${summary.runAddr.toString(16).toUpperCase().padStart(4, "0")}`
      : "n/a";

  console.log(`Source     : ${path.relative(repoRoot, summary.sourcePath)}`);
  console.log(`XEX        : ${path.relative(repoRoot, summary.xexOutput)}`);
  console.log(`Run addr   : ${runAddr}`);
  console.log(`Screenshot : ${path.relative(repoRoot, summary.screenshotPath)}`);
  console.log(`Artifacts  : ${path.relative(repoRoot, summary.artifactsPath)}`);
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
});
