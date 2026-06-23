import { chromium } from 'playwright-core';
import http from 'node:http';
import fs from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';

const runDir = requiredEnv('RUN_DIR');
const runId = process.env.RUN_ID ?? path.basename(runDir);
const observerPort = Number(process.env.OBSERVER_PORT ?? '0');
const remoteDebuggingPort = process.env.CHROME_REMOTE_DEBUGGING_PORT ?? '';
const chromePath = process.env.CHROME_PATH ?? '';
const iterations = Number(process.env.ITERATIONS ?? '1');
const keepOpen = process.env.HISLE_CHROME_KEEP_OPEN === '1';
const traceEnabled = process.env.HISLE_CHROME_TRACE !== '0';
const expectedUnit = 'f`\u{C758}f\u{C5B4}\u{315C}f';
const expectedValue = process.env.EXPECTED_VALUE ?? expectedUnit.repeat(iterations);
const readyFile = path.join(runDir, 'observer-ready.json');
const pidFile = path.join(runDir, 'observer.pid');
const userDataDir = path.join(runDir, 'chrome-profile');

let context;
let page;
let server;
let finalized = false;

await fs.mkdir(runDir, { recursive: true });
await fs.writeFile(pidFile, `${process.pid}\n`, 'utf8');

try {
  await startBrowser();
  await startServer();
  await writeReadyFile();
  console.log(`observer ready on http://127.0.0.1:${server.address().port}`);
} catch (error) {
  await writeFailureState(error);
  console.error(error?.stack ?? String(error));
  process.exit(1);
}

process.on('SIGTERM', () => {
  finalize({ reason: 'sigterm', driverExitCode: 143 })
    .finally(() => process.exit(143));
});

process.on('SIGINT', () => {
  finalize({ reason: 'sigint', driverExitCode: 130 })
    .finally(() => process.exit(130));
});

function requiredEnv(name) {
  const value = process.env[name];
  if (!value) {
    throw new Error(`${name} is required`);
  }
  return value;
}

async function startBrowser() {
  const launchOptions = {
    headless: false,
    chromiumSandbox: true,
    viewport: { width: 1200, height: 800 },
    args: [
      '--no-first-run',
      '--no-default-browser-check',
      '--disable-search-engine-choice-screen',
    ],
  };

  if (chromePath) {
    launchOptions.executablePath = chromePath;
  } else {
    launchOptions.channel = 'chrome';
  }

  if (remoteDebuggingPort) {
    launchOptions.args.push(`--remote-debugging-port=${remoteDebuggingPort}`);
  }

  context = await chromium.launchPersistentContext(userDataDir, launchOptions);

  if (traceEnabled) {
    await context.tracing.start({ screenshots: true, snapshots: true, sources: false });
  }

  page = context.pages()[0] ?? await context.newPage();
  await page.setViewportSize({ width: 1200, height: 800 });
  await installTestPage(page);
}

async function installTestPage(targetPage) {
  await targetPage.setContent(`<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>hisle Chrome IME Repro</title>
  <style>
    html,
    body {
      margin: 0;
      min-height: 100%;
      font: 16px -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      color: #1d1d1f;
      background: #f6f8fa;
    }

    main {
      box-sizing: border-box;
      min-height: 100vh;
      padding: 8vh 8vw;
      display: grid;
      grid-template-rows: auto 1fr;
      gap: 20px;
    }

    h1 {
      margin: 0;
      font-size: 20px;
      font-weight: 600;
    }

    textarea {
      box-sizing: border-box;
      width: 100%;
      min-height: 58vh;
      padding: 18px;
      border: 2px solid #2563eb;
      border-radius: 8px;
      font: 28px "Apple SD Gothic Neo", "Noto Sans CJK KR", Menlo, monospace;
      line-height: 1.45;
      resize: none;
      background: white;
      color: #111827;
      outline: none;
    }

    textarea:focus {
      border-color: #0f766e;
      box-shadow: 0 0 0 4px rgba(15, 118, 110, 0.18);
    }
  </style>
</head>
<body>
  <main>
    <h1>hisle Chrome IME Repro</h1>
    <textarea id="target" autofocus spellcheck="false" autocapitalize="off" autocomplete="off"></textarea>
  </main>
</body>
</html>`);

  await targetPage.evaluate(() => {
    const textarea = document.getElementById('target');
    const eventTypes = [
      'keydown',
      'keyup',
      'compositionstart',
      'compositionupdate',
      'compositionend',
      'beforeinput',
      'input',
      'selectionchange',
      'focus',
      'blur',
    ];

    window.__hisleEvents = [];
    window.__hisleEventSequence = 0;

    function activeElementIdentity() {
      const element = document.activeElement;
      if (!element) {
        return null;
      }
      return {
        tagName: element.tagName,
        id: element.id || null,
        name: element.getAttribute('name'),
      };
    }

    function eventValue(event, key) {
      return Object.prototype.hasOwnProperty.call(event, key) ? event[key] : null;
    }

    function record(event) {
      const eventTimestamp = Number(event.timeStamp ?? performance.now());
      const wallClockTimestamp = new Date(performance.timeOrigin + eventTimestamp).toISOString();

      window.__hisleEvents.push({
        sequence: ++window.__hisleEventSequence,
        performance_now: performance.now(),
        event_timestamp: eventTimestamp,
        wall_clock_timestamp: wallClockTimestamp,
        event_type: event.type,
        key: eventValue(event, 'key'),
        code: eventValue(event, 'code'),
        repeat: eventValue(event, 'repeat'),
        data: eventValue(event, 'data'),
        input_type: eventValue(event, 'inputType'),
        is_composing: eventValue(event, 'isComposing'),
        value: textarea.value,
        selection_start: textarea.selectionStart,
        selection_end: textarea.selectionEnd,
        active_element: activeElementIdentity(),
      });
    }

    for (const type of eventTypes) {
      document.addEventListener(type, record, { capture: true });
    }

    textarea.focus();
    window.__hisleReady = document.activeElement === textarea;
  });

  await targetPage.waitForFunction(() => window.__hisleReady === true);
  await targetPage.bringToFront();
}

async function startServer() {
  server = http.createServer((request, response) => {
    if (request.method === 'GET' && request.url === '/ready') {
      writeJSON(response, 200, { ok: true, runId, runDir });
      return;
    }

    if (request.method === 'POST' && request.url === '/finish') {
      readBody(request)
        .then((body) => {
          let payload = {};
          if (body.length > 0) {
            payload = JSON.parse(body);
          }
          return finalize({
            reason: payload.reason ?? 'finish',
            driverExitCode: Number(payload.driver_exit_code ?? 0),
          });
        })
        .then((result) => {
          writeJSON(response, 200, result);
          server.close(() => {
            process.exit(result.ok ? 0 : 2);
          });
        })
        .catch((error) => {
          writeJSON(response, 500, { ok: false, error: String(error?.stack ?? error) });
          server.close(() => process.exit(1));
        });
      return;
    }

    writeJSON(response, 404, { ok: false, error: 'not found' });
  });

  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(observerPort, '127.0.0.1', () => {
      server.off('error', reject);
      resolve();
    });
  });
}

async function writeReadyFile() {
  const browser = context.browser();
  const ready = {
    ok: true,
    run_id: runId,
    run_directory: runDir,
    observer_port: server.address().port,
    ready_wall_clock_timestamp: new Date().toISOString(),
    chrome_path: chromePath || null,
    chrome_version: browser ? browser.version() : null,
    remote_debugging_port: remoteDebuggingPort || null,
    user_data_dir: userDataDir,
  };
  await fs.writeFile(readyFile, `${JSON.stringify(ready, null, 2)}\n`, 'utf8');
}

async function readBody(request) {
  const chunks = [];
  for await (const chunk of request) {
    chunks.push(chunk);
  }
  return Buffer.concat(chunks).toString('utf8');
}

function writeJSON(response, statusCode, value) {
  const body = `${JSON.stringify(value)}\n`;
  response.writeHead(statusCode, {
    'content-type': 'application/json; charset=utf-8',
    'content-length': Buffer.byteLength(body),
  });
  response.end(body);
}

async function finalize({ reason, driverExitCode }) {
  if (finalized) {
    return { ok: true, already_finalized: true };
  }
  finalized = true;

  const domEvents = page ? await page.evaluate(() => window.__hisleEvents ?? []) : [];
  await writeJSONLines(path.join(runDir, 'dom-events.jsonl'), domEvents);

  const finalState = page ? await page.evaluate((expected) => {
    const textarea = document.getElementById('target');
    const active = document.activeElement;
    const activeElement = active ? {
      tagName: active.tagName,
      id: active.id || null,
      name: active.getAttribute('name'),
    } : null;
    return {
      wall_clock_timestamp: new Date().toISOString(),
      performance_now: performance.now(),
      value: textarea.value,
      selection_start: textarea.selectionStart,
      selection_end: textarea.selectionEnd,
      active_element: activeElement,
      event_count: window.__hisleEvents?.length ?? 0,
      expected_value: expected,
      matches_expected_value: textarea.value === expected,
    };
  }, expectedValue) : {
    wall_clock_timestamp: new Date().toISOString(),
    value: '',
    expected_value: expectedValue,
    matches_expected_value: false,
  };

  finalState.reason = reason;
  finalState.driver_exit_code = driverExitCode;

  await fs.writeFile(
    path.join(runDir, 'final-state.json'),
    `${JSON.stringify(finalState, null, 2)}\n`,
    'utf8',
  );

  if (page) {
    await page.screenshot({ path: path.join(runDir, 'screenshot.png'), fullPage: true });
  }

  if (traceEnabled && context) {
    await context.tracing.stop({ path: path.join(runDir, 'trace.zip') });
  }

  if (!keepOpen && context) {
    await context.close();
  }

  const ok = driverExitCode === 0 && finalState.matches_expected_value === true;
  return {
    ok,
    reason,
    driver_exit_code: driverExitCode,
    matches_expected_value: finalState.matches_expected_value,
    value: finalState.value,
    expected_value: expectedValue,
    event_count: finalState.event_count,
  };
}

async function writeJSONLines(filePath, records) {
  const text = records.map((record) => JSON.stringify(record)).join('\n');
  await fs.writeFile(filePath, text.length > 0 ? `${text}\n` : '', 'utf8');
}

async function writeFailureState(error) {
  await fs.writeFile(
    path.join(runDir, 'final-state.json'),
    `${JSON.stringify({
      wall_clock_timestamp: new Date().toISOString(),
      value: '',
      expected_value: expectedValue,
      matches_expected_value: false,
      setup_error: String(error?.stack ?? error),
    }, null, 2)}\n`,
    'utf8',
  );
}
