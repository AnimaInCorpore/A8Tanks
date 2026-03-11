#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");

const { createStaticServer } = require("./lib/static_server");
const { repoRoot } = require("./lib/jsa8e_assembler");
const { convertXexToAtr } = require("./lib/xex_to_atr");

function printHelp() {
  console.log(`Usage: node tools/run.js [options]

Options:
  --source <path>      Assembly source file to assemble and run
  --os-rom <path>      Path to ATARIXL.ROM
  --basic-rom <path>   Path to ATARIBAS.ROM
  --port <number>      Static server port (default: random free port)
  --show               Launch Chromium with a visible window
  --timeout-ms <ms>    Breakpoint wait timeout / failure snapshot timeout (default: 5000)
  --xex-output <path>  Where to write the assembled XEX
  --atr-output <path>  Where to write the converted ATR
  --screenshot <path>  Where to write the captured PNG
  --artifacts <path>   Where to write the JSON run or failure artifacts
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
    if (arg === "--atr-output") {
      options.atrOutput = argv[index + 1];
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

function defaultAtrOutputFor(xexOutputPath) {
  return path.join(
    path.dirname(xexOutputPath),
    `${path.basename(xexOutputPath, path.extname(xexOutputPath))}.atr`,
  );
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

function relativeToRepo(filePath) {
  return path.relative(repoRoot, filePath);
}

function summarizeBuild(build) {
  if (!build || typeof build !== "object") return null;
  return {
    ok: build.ok !== false,
    byteLength:
      typeof build.byteLength === "number"
        ? build.byteLength
        : build.bytes && typeof build.bytes.length === "number"
          ? build.bytes.length
          : null,
    error: build.error || null,
    errors: Array.isArray(build.errors) ? build.errors : [],
    runAddr: typeof build.runAddr === "number" ? build.runAddr : null,
    sourceName: build.sourceName || null,
    symbols: build.symbols || null,
  };
}

function getArtifactScreenshotBase64(artifacts) {
  if (!artifacts || typeof artifacts !== "object") return null;
  if (!artifacts.screenshot || typeof artifacts.screenshot !== "object") return null;
  return typeof artifacts.screenshot.base64 === "string" ? artifacts.screenshot.base64 : null;
}

function toBuffer(data) {
  if (!data) return null;
  if (Buffer.isBuffer(data)) return data;
  if (ArrayBuffer.isView(data)) {
    return Buffer.from(data.buffer, data.byteOffset, data.byteLength);
  }
  if (data instanceof ArrayBuffer) return Buffer.from(data);
  if (Array.isArray(data)) return Buffer.from(data);
  if (typeof data.length === "number") return Buffer.from(Array.from(data));
  return null;
}

function isFailureArtifact(value) {
  return !!(
    value &&
    typeof value === "object" &&
    value.artifactSchemaVersion &&
    value.failure
  );
}

function buildArtifactRecord(result, context) {
  const base =
    result && result.artifacts && typeof result.artifacts === "object"
      ? Object.assign({}, result.artifacts)
      : {};

  if (result && result.capabilities) base.capabilities = result.capabilities;
  if (result && result.systemState) base.systemState = result.systemState;

  base.toolRun = {
    tool: "tools/run.js",
    ok: !!(result && result.ok),
    stage: result && result.stage ? result.stage : result && result.ok ? "complete" : "failed",
    source: relativeToRepo(context.sourcePath),
    outputs: {
      artifacts: relativeToRepo(context.artifactsPath),
      atr: relativeToRepo(context.atrOutput),
      screenshot: relativeToRepo(context.screenshotPath),
      xex: relativeToRepo(context.xexOutput),
    },
    timeoutMs: context.timeoutMs,
  };
  base.roms = {
    basic: relativeToRepo(context.basicRomPath),
    os: relativeToRepo(context.osRomPath),
  };
  if (result && Array.isArray(result.progressEvents)) {
    base.progressEvents = result.progressEvents;
  }
  if (result && result.build) base.build = summarizeBuild(result.build);
  if (result && result.run) base.run = result.run;
  if (result && result.stop && !isFailureArtifact(result.stop)) base.stop = result.stop;

  return base;
}

function formatBuildErrors(build) {
  if (!build || !Array.isArray(build.errors) || !build.errors.length) return "";
  return build.errors
    .map((entry) => {
      const lineNo =
        entry && entry.lineNo !== undefined && entry.lineNo !== null
          ? `line ${entry.lineNo}: `
          : "";
      return `${lineNo}${entry && entry.message ? entry.message : "Unknown error."}`;
    })
    .join("\n");
}

function formatFailureMessage(result) {
  if (result && result.stage === "assemble") {
    const headline =
      result.build && result.build.error
        ? String(result.build.error)
        : "jsA8E assembly failed.";
    const details = formatBuildErrors(result.build);
    return details ? `${headline}\n${details}` : headline;
  }

  if (result && isFailureArtifact(result.artifacts)) {
    const failure = result.artifacts.failure || {};
    const phase = result.artifacts.phase ? ` (${result.artifacts.phase})` : "";
    const message =
      failure.message || `jsA8E automation failed during ${result.stage || "run"}.`;
    return `${message}${phase}`;
  }

  return `jsA8E automation failed during ${result && result.stage ? result.stage : "run"}.`;
}

async function runInBrowser(options) {
  const { chromium } = requirePlaywright();
  const sourcePath = resolveRepoPath(options.source || "src/a8tanks.asm");
  const sourceName = path.relative(repoRoot, sourcePath).replace(/\\/g, "/");
  const sourceText = fs.readFileSync(sourcePath, "utf8");

  const baseName = path.basename(sourcePath, path.extname(sourcePath));
  const xexOutput = resolveRepoPath(options.xexOutput || `build/${baseName}.xex`);
  const atrOutput = resolveRepoPath(options.atrOutput || defaultAtrOutputFor(xexOutput));
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
        let api = null;
        let progressToken = 0;
        const progressEvents = [];

        try {
          api = await window.A8EAutomation.whenReady();
          if (api.events && typeof api.events.subscribe === "function") {
            progressToken = api.events.subscribe("progress", (event) => {
              progressEvents.push(Object.assign({}, event));
            });
          }

          const capabilities = await api.getCapabilities();
          const artifactOptions = {
            screenshot: true,
            traceTailLimit: 64,
            runConfiguration: {
              sourceName: sourceName,
              timeoutMs: timeoutMs,
            },
            scenarioMarkers: {
              sourceName: sourceName,
            },
          };

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
              artifacts:
                capabilities && capabilities.failureSnapshots
                  ? await api.artifacts.captureFailureState(
                      Object.assign({}, artifactOptions, {
                        operation: "assembleSource",
                        failure: {
                          message:
                            build && build.error ? String(build.error) : "Assembly failed",
                          reason: "assemble_failed",
                        },
                      }),
                    )
                  : null,
              build: build,
              capabilities: capabilities,
              progressEvents: progressEvents,
              systemState: await api.getSystemState(),
            };
          }

          const entryPoint = typeof build.runAddr === "number" ? build.runAddr : 0x2000;
          artifactOptions.runConfiguration.entryPoint = entryPoint;
          artifactOptions.scenarioMarkers.entryPoint = entryPoint;
          await api.debug.setBreakpoints([entryPoint]);

          const run = await api.dev.runXex({
            build: build,
            saveHostFile: true,
          });

          const stop = await api.debug.waitForBreakpoint(
            Object.assign({}, artifactOptions, {
              operation: "waitForBreakpoint",
              targetPc: entryPoint,
              timeoutMs: timeoutMs,
            }),
          );

          if (!stop || stop.ok === false) {
            return {
              ok: false,
              stage: "waitForBreakpoint",
              artifacts:
                stop && stop.artifactSchemaVersion
                  ? stop
                  : await api.artifacts.captureFailureState(
                      Object.assign({}, artifactOptions, {
                        operation: "waitForBreakpoint",
                        targetPc: entryPoint,
                        timeoutMs: timeoutMs,
                        failure: {
                          message: "Breakpoint wait failed",
                          reason: "breakpoint_wait_failed",
                          targetPc: entryPoint,
                          timeoutMs: timeoutMs,
                        },
                      }),
                    ),
              build: build,
              capabilities: capabilities,
              progressEvents: progressEvents,
              run: run,
              stop: stop,
              systemState: await api.getSystemState(),
            };
          }

          const artifacts = await api.artifacts.collectArtifacts(
            Object.assign({}, artifactOptions, {
              operation: "tools.run",
            }),
          );

          return {
            ok: true,
            artifacts: artifacts,
            build: build,
            capabilities: capabilities,
            progressEvents: progressEvents,
            run: run,
            stop: stop,
            systemState: await api.getSystemState(),
          };
        } finally {
          if (
            api &&
            progressToken &&
            api.events &&
            typeof api.events.unsubscribe === "function"
          ) {
            api.events.unsubscribe(progressToken);
          }
        }
      },
      {
        basicBase64: basicBase64,
        osBase64: osBase64,
        sourceName: sourceName,
        sourceText: sourceText,
        timeoutMs: options.timeoutMs,
      },
    );

    const xexBytes = toBuffer(result && result.build ? result.build.bytes : null);
    if (xexBytes) {
      ensureParentDir(xexOutput);
      fs.writeFileSync(xexOutput, xexBytes);
    }

    const artifactRecord = buildArtifactRecord(result || {}, {
      artifactsPath: artifactsPath,
      atrOutput: atrOutput,
      basicRomPath: basicRomPath,
      osRomPath: osRomPath,
      screenshotPath: screenshotPath,
      sourcePath: sourcePath,
      timeoutMs: options.timeoutMs,
      xexOutput: xexOutput,
    });
    writeJson(artifactsPath, artifactRecord);

    const screenshotBase64 = getArtifactScreenshotBase64(result && result.artifacts);
    if (screenshotBase64) {
      ensureParentDir(screenshotPath);
      fs.writeFileSync(screenshotPath, Buffer.from(screenshotBase64, "base64"));
    }

    if (xexBytes) {
      const atrBytes = convertXexToAtr(xexBytes);
      if (!atrBytes) {
        throw new Error("Unable to convert assembled XEX into a bootable ATR.");
      }
      ensureParentDir(atrOutput);
      fs.writeFileSync(atrOutput, atrBytes);
    }

    if (!result || !result.ok) {
      throw new Error(formatFailureMessage(result));
    }

    return {
      artifactsPath: artifactsPath,
      atrOutput: atrOutput,
      runAddr: result.build.runAddr,
      screenshotPath: screenshotBase64 ? screenshotPath : null,
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
  console.log(`ATR        : ${path.relative(repoRoot, summary.atrOutput)}`);
  console.log(`Run addr   : ${runAddr}`);
  console.log(
    `Screenshot : ${
      summary.screenshotPath ? path.relative(repoRoot, summary.screenshotPath) : "n/a"
    }`,
  );
  console.log(`Artifacts  : ${path.relative(repoRoot, summary.artifactsPath)}`);
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
});
