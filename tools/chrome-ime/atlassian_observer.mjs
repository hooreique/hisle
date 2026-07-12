import { chromium } from 'playwright-core';
import { spawn } from 'node:child_process';
import http from 'node:http';
import net from 'node:net';
import fs from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';

import { installDOMEventRecorder } from './dom_event_recorder.mjs';
import {
  confluencePageIdentity,
  findPageWithConfluenceIdentity,
  hasSameConfluencePageIdentity,
} from './atlassian_page_identity.mjs';
import { expectedDocumentState } from './atlassian_scenario_contract.mjs';
import {
  ObserverLifecycle,
  closeConnectedChromium,
  closeHttpServer,
} from './observer_lifecycle.mjs';

const runDir = requiredEnv('RUN_DIR');
const profileDir = requiredEnv('ATLASSIAN_PROFILE_DIR');
const requestedPageURL = requiredEnv('ATLASSIAN_CONFLUENCE_URL');
const runId = process.env.RUN_ID ?? path.basename(runDir);
const observerPort = Number(process.env.OBSERVER_PORT ?? '0');
const remoteDebuggingPort = process.env.CHROME_REMOTE_DEBUGGING_PORT ?? '';
const chromePath = process.env.CHROME_PATH ?? '';
const chromeApp = process.env.HISLE_ATLASSIAN_CHROME_APP ?? 'Google Chrome';
const useNormalChrome = process.env.HISLE_ATLASSIAN_NORMAL_CHROME !== '0';
const reuseNormalChrome = process.env.HISLE_ATLASSIAN_REUSE_CHROME === '1';
const loginOnly = process.env.HISLE_ATLASSIAN_LOGIN_ONLY === '1';
const expectedText = loginOnly ? '' : requiredEnv('HISLE_ATLASSIAN_EXPECTED_TEXT');
const targetSelector = process.env.HISLE_ATLASSIAN_TARGET_SELECTOR ?? '';
const editPage = process.env.HISLE_ATLASSIAN_EDIT !== '0';
const keepOpen = process.env.HISLE_ATLASSIAN_KEEP_OPEN === '1';
const traceEnabled = process.env.HISLE_ATLASSIAN_TRACE === '1';
const allowMismatch = process.env.HISLE_ATLASSIAN_ALLOW_MISMATCH === '1';
const editorTimeoutMilliseconds = numberFromEnv('HISLE_ATLASSIAN_EDITOR_TIMEOUT_MS', 90000);
const configuredWindowTitleContains = process.env.HISLE_ATLASSIAN_WINDOW_TITLE_CONTAINS ?? '';
const initialCaretOffsetText = process.env.HISLE_ATLASSIAN_INITIAL_CARET_OFFSET ?? '';
const readyFile = path.join(runDir, 'observer-ready.json');
const pidFile = path.join(runDir, 'observer.pid');
const supervisorPID = processIDFromEnv('HISLE_SUPERVISOR_PID');
const controlPID = supervisorPID ?? process.pid;

let context;
let browser;
let page;
let server;
let connectedToNormalChrome = false;
let ownsNormalChrome = false;
let normalChromeProcess;
let preserveBrowser = false;
let shutdownRequest = null;
let resolveShutdown;
let setupComplete = false;
let runClaimed = false;
let cleanupPromise = null;
const runtimeLifecycle = new ObserverLifecycle();
const browserLifecycle = new ObserverLifecycle();
const shutdownPromise = new Promise((resolve) => {
  resolveShutdown = resolve;
});
const consoleRecords = [];

for (const [signal, driverExitCode, signalExitCode] of [
  ['SIGTERM', 143, 143],
  ['SIGINT', loginOnly ? 0 : 130, loginOnly ? 0 : 130],
  ['SIGHUP', 129, 129],
]) {
  process.on(signal, () => {
    requestObserverShutdown({
      reason: signal.toLowerCase(),
      driverExitCode,
      exitCode: signalExitCode,
    });
  });
}
process.on('uncaughtException', (error) => {
  requestObserverShutdown({ reason: 'uncaught-exception', driverExitCode: 1, exitCode: 1, error });
});
process.on('unhandledRejection', (reason) => {
  const error = reason instanceof Error ? reason : new Error(String(reason));
  requestObserverShutdown({ reason: 'unhandled-rejection', driverExitCode: 1, exitCode: 1, error });
});

let exitCode = 1;
try {
  await fs.mkdir(runDir, { recursive: true });
  await fs.mkdir(profileDir, { recursive: true });
  await fs.writeFile(pidFile, `${controlPID}\n`, { encoding: 'utf8', flag: 'wx' });
  runClaimed = true;
  startSupervisorWatchdog();

  if (!loginOnly) {
    requiredRequestedPageIdentity();
  }
  await startBrowser();
  await startServer();

  if (!loginOnly) {
    await prepareConfluenceEditor();
  }

  await writeReadyFile();
  setupComplete = true;
  const mode = loginOnly ? 'login profile' : 'Confluence editor';
  console.log(`Atlassian observer ready for ${mode} on http://127.0.0.1:${server.address().port}`);

  if (loginOnly) {
    console.log(`Profile directory: ${profileDir}`);
    console.log('Complete the browser sign-in, then press Ctrl-C in this terminal to close the observer.');
  }

  const request = await shutdownPromise;
  if (request.error) {
    throw request.error;
  }
  const result = await finalize({
    reason: request.reason,
    driverExitCode: request.driverExitCode,
  });
  preserveBrowser = Boolean(request.response) && keepOpen && result.ok;
  if (request.response) {
    writeJSON(request.response, 200, result);
  }
  exitCode = request.exitCode ?? (result.ok ? 0 : 2);
} catch (error) {
  if (runClaimed) {
    await writeFailureState(error).catch((writeError) => {
      console.error(writeError?.stack ?? String(writeError));
    });
  }
  if (shutdownRequest?.response && !shutdownRequest.response.headersSent) {
    writeJSON(shutdownRequest.response, 500, {
      ok: false,
      error: String(error?.stack ?? error),
    });
  }
  console.error(error?.stack ?? String(error));
  exitCode = shutdownRequest?.exitCode ?? 1;
} finally {
  const cleanup = await disposeResources();
  for (const failure of cleanup.errors) {
    console.error(`Cleanup failed (${failure.label}): ${failure.error?.stack ?? failure.error}`);
  }
  if (cleanup.errors.length > 0 && exitCode === 0) {
    exitCode = 1;
  }
}

process.exit(exitCode);

function requestObserverShutdown(request) {
  if (shutdownRequest) {
    if (request.response && !request.response.headersSent) {
      writeJSON(request.response, 409, { ok: false, error: 'observer shutdown already requested' });
    }
    return false;
  }

  shutdownRequest = request;
  resolveShutdown(request);
  if (!setupComplete) {
    void disposeResources();
  }
  return true;
}

function requiredEnv(name) {
  const value = process.env[name];
  if (!value) {
    throw new Error(`${name} is required`);
  }
  return value;
}

function numberFromEnv(name, fallback) {
  const text = process.env[name];
  if (!text) {
    return fallback;
  }
  const value = Number(text);
  return Number.isFinite(value) ? value : fallback;
}

function processIDFromEnv(name) {
  const text = process.env[name] ?? '';
  if (!text) {
    return null;
  }
  const value = Number(text);
  if (!Number.isInteger(value) || value <= 0) {
    throw new Error(`${name} must be a positive process ID.`);
  }
  return value;
}

function throwIfShutdownRequested() {
  if (cleanupPromise) {
    throw new Error(`Observer shutdown requested during setup: ${shutdownRequest?.reason ?? 'unknown'}`);
  }
}

function startSupervisorWatchdog() {
  if (!supervisorPID) {
    return;
  }
  if (process.ppid !== supervisorPID) {
    throw new Error(`Observer supervisor mismatch: expected parent ${supervisorPID}, got ${process.ppid}.`);
  }

  const watchdog = setInterval(() => {
    if (process.ppid !== supervisorPID || !processIsAlive(supervisorPID)) {
      requestObserverShutdown({
        reason: 'supervisor-exited',
        driverExitCode: 1,
        exitCode: 1,
      });
    }
  }, 250);
  runtimeLifecycle.defer('supervisor-watchdog', () => clearInterval(watchdog));
}

function processIsAlive(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

function disposeResources() {
  if (!cleanupPromise) {
    cleanupPromise = (async () => {
      const runtimeCleanup = await runtimeLifecycle.dispose();
      if (runtimeCleanup.errors.length > 0) {
        preserveBrowser = false;
      }
      const browserCleanup = await browserLifecycle.dispose();
      return { errors: [...runtimeCleanup.errors, ...browserCleanup.errors] };
    })();
  }
  return cleanupPromise;
}

function initialCaretOffsetFromText(text) {
  if (!text) {
    return null;
  }

  if (text === 'middle') {
    return 'middle';
  }

  const value = Number(text);
  return Number.isInteger(value) && value >= 0 ? value : null;
}

async function startBrowser() {
  if (useNormalChrome) {
    await startNormalChromeBrowser();
    return;
  }

  const launchOptions = {
    headless: false,
    chromiumSandbox: true,
    viewport: { width: 1400, height: 900 },
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

  context = await browserLifecycle.acquire(
    'chromium-context',
    () => chromium.launchPersistentContext(profileDir, launchOptions),
    (acquiredContext) => acquiredContext.close(),
  );
  throwIfShutdownRequested();
  browser = context.browser();
  context.on('page', wirePage);

  if (traceEnabled) {
    await runtimeLifecycle.acquire(
      'chromium-trace',
      async () => {
        await context.tracing.start({ screenshots: true, snapshots: true, sources: false });
        return context.tracing;
      },
      (tracing) => tracing.stop({ path: path.join(runDir, 'trace.zip') }),
    );
    throwIfShutdownRequested();
  }

  page = context.pages()[0] ?? await context.newPage();
  wirePage(page);
  await page.setViewportSize({ width: 1400, height: 900 });
  await page.goto(requestedPageURL, { waitUntil: 'domcontentloaded', timeout: 120000 });
  await page.bringToFront();
}

async function startNormalChromeBrowser() {
  if (!remoteDebuggingPort) {
    throw new Error('CHROME_REMOTE_DEBUGGING_PORT is required when using normal Chrome for Atlassian repros.');
  }

  const chromeArgs = [
    `--user-data-dir=${profileDir}`,
    `--remote-debugging-port=${remoteDebuggingPort}`,
    '--no-first-run',
    '--no-default-browser-check',
    '--enable-automation',
    requestedPageURL,
  ];

  const cdpURL = `http://127.0.0.1:${remoteDebuggingPort}`;
  if (reuseNormalChrome) {
    await waitForCDP(cdpURL);
  } else {
    await assertCDPPortAvailable(remoteDebuggingPort);
    normalChromeProcess = await browserLifecycle.acquire(
      'normal-chrome-process',
      async () => {
        const executable = await normalChromeExecutable();
        const child = spawn(executable, chromeArgs, { stdio: 'ignore' });
        await new Promise((resolve, reject) => {
          child.once('spawn', resolve);
          child.once('error', reject);
        });
        return child;
      },
      async (child) => {
        if (!preserveBrowser) {
          await stopNormalChromeProcess(child);
        }
      },
    );
    throwIfShutdownRequested();
    await waitForCDP(cdpURL);
  }
  browser = await browserLifecycle.acquire(
    'connected-chromium',
    () => chromium.connectOverCDP(cdpURL),
    (connectedBrowser) => closeConnectedChromium({
      browser: connectedBrowser,
      owned: ownsNormalChrome && !preserveBrowser,
    }),
  );
  throwIfShutdownRequested();
  connectedToNormalChrome = true;
  if (normalChromeProcess) {
    await verifyOwnedNormalChrome(browser);
    ownsNormalChrome = true;
  }
  context = browser.contexts()[0];
  if (!context) {
    throw new Error('Could not find the default Chrome context after connecting over CDP.');
  }
  context.on('page', wirePage);

  if (traceEnabled) {
    await runtimeLifecycle.acquire(
      'chromium-trace',
      async () => {
        await context.tracing.start({ screenshots: true, snapshots: true, sources: false });
        return context.tracing;
      },
      (tracing) => tracing.stop({ path: path.join(runDir, 'trace.zip') }),
    ).catch((error) => {
      consoleRecords.push({
        wall_clock_timestamp: new Date().toISOString(),
        type: 'trace-start-error',
        text: String(error?.stack ?? error).slice(0, 4000),
        location: null,
      });
    });
    throwIfShutdownRequested();
  }

  page = await pageForRequestedURL(context);
  wirePage(page);
  await page.setViewportSize({ width: 1400, height: 900 }).catch(() => {});
  await page.waitForLoadState('domcontentloaded', { timeout: 60000 }).catch(() => {});
  await page.bringToFront();
}

async function waitForCDP(cdpURL) {
  const deadline = Date.now() + 45000;
  let lastError = null;

  while (Date.now() < deadline) {
    throwIfShutdownRequested();
    try {
      const response = await fetch(`${cdpURL}/json/version`);
      if (response.ok) {
        return;
      }
      lastError = new Error(`CDP status ${response.status}`);
    } catch (error) {
      lastError = error;
    }
    await new Promise((resolve) => setTimeout(resolve, 250));
  }

  throw new Error(`Timed out waiting for Chrome CDP endpoint at ${cdpURL}: ${lastError}`);
}

async function assertCDPPortAvailable(portText) {
  const port = Number(portText);
  if (!Number.isInteger(port) || port <= 0 || port > 65535) {
    throw new Error(`CHROME_REMOTE_DEBUGGING_PORT must be an unused TCP port: ${portText}`);
  }

  await new Promise((resolve, reject) => {
    const socket = net.createConnection({ host: '127.0.0.1', port });
    const timeout = setTimeout(() => {
      socket.destroy();
      reject(new Error(`Could not verify that Chrome remote debugging port ${port} is unused.`));
    }, 1000);
    socket.once('connect', () => {
      clearTimeout(timeout);
      socket.destroy();
      reject(new Error(`Chrome remote debugging port ${port} is already in use.`));
    });
    socket.once('error', (error) => {
      clearTimeout(timeout);
      socket.destroy();
      if (error?.code === 'ECONNREFUSED') {
        resolve();
      } else {
        reject(error);
      }
    });
  });
}

async function verifyOwnedNormalChrome(connectedBrowser) {
  const session = await connectedBrowser.newBrowserCDPSession();
  try {
    const commandLine = await session.send('Browser.getBrowserCommandLine');
    const expectedProfileArgument = `--user-data-dir=${profileDir}`;
    if (!commandLine.arguments?.includes(expectedProfileArgument)) {
      throw new Error('Connected Chrome does not own the configured Atlassian profile.');
    }
  } finally {
    await session.detach().catch(() => {});
  }
}

async function normalChromeExecutable() {
  if (chromePath) {
    return chromePath;
  }

  const appName = chromeApp.endsWith('.app') ? chromeApp.slice(0, -4) : chromeApp;
  const candidates = [
    path.join('/Applications', `${appName}.app`, 'Contents', 'MacOS', appName),
    path.join(process.env.HOME ?? '', 'Applications', `${appName}.app`, 'Contents', 'MacOS', appName),
  ];
  for (const candidate of candidates) {
    try {
      await fs.access(candidate);
      return candidate;
    } catch {
      // Try the next standard application location.
    }
  }

  throw new Error(`Could not resolve ${chromeApp}; set CHROME_PATH to the Chrome executable.`);
}

async function stopNormalChromeProcess(child = normalChromeProcess) {
  if (!child || child.exitCode !== null || child.signalCode !== null) {
    return;
  }

  child.kill('SIGTERM');
  if (!await waitForProcessExit(child, 5000)) {
    child.kill('SIGKILL');
    if (!await waitForProcessExit(child, 2000)) {
      throw new Error(`Owned Chrome process ${child.pid ?? 'unknown'} did not exit after SIGKILL.`);
    }
  }
}

async function waitForProcessExit(child, timeoutMilliseconds) {
  const deadline = Date.now() + timeoutMilliseconds;
  while (child.exitCode === null && child.signalCode === null && Date.now() < deadline) {
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  return child.exitCode !== null || child.signalCode !== null;
}

async function pageForRequestedURL(targetContext) {
  const deadline = Date.now() + 30000;

  while (Date.now() < deadline) {
    const candidates = targetContext.pages();
    for (const candidate of candidates) {
      wirePage(candidate);
    }

    const matchingPage = findPageWithConfluenceIdentity(candidates, requestedPageURL);
    if (matchingPage) {
      return matchingPage;
    }
    await new Promise((resolve) => setTimeout(resolve, 250));
  }

  const dedicatedPage = await targetContext.newPage();
  wirePage(dedicatedPage);
  await dedicatedPage.goto(requestedPageURL, { waitUntil: 'domcontentloaded', timeout: 120000 });
  return dedicatedPage;
}

function wirePage(targetPage) {
  if (targetPage.__hisleAtlassianWired) {
    return;
  }
  targetPage.__hisleAtlassianWired = true;

  targetPage.on('console', (message) => {
    consoleRecords.push({
      wall_clock_timestamp: new Date().toISOString(),
      type: message.type(),
      text: message.text().slice(0, 4000),
      location: message.location(),
    });
  });

  targetPage.on('pageerror', (error) => {
    consoleRecords.push({
      wall_clock_timestamp: new Date().toISOString(),
      type: 'pageerror',
      text: String(error?.stack ?? error).slice(0, 4000),
      location: null,
    });
  });
}

function requiredRequestedPageIdentity() {
  const requestedIdentity = confluencePageIdentity(requestedPageURL);
  if (!requestedIdentity?.pageId) {
    throw new Error(
      'ATLASSIAN_CONFLUENCE_URL must identify a Confluence page with a numeric page ID.'
    );
  }
  return requestedIdentity;
}

function requireConfiguredPageIdentity(stage) {
  const requestedIdentity = requiredRequestedPageIdentity();
  const currentPageURL = page.url();
  const currentIdentity = confluencePageIdentity(currentPageURL);
  if (!hasSameConfluencePageIdentity(currentPageURL, requestedPageURL)) {
    const currentSummary = currentIdentity?.pageId
      ? `${currentIdentity.origin} page ${currentIdentity.pageId}`
      : 'an unrecognized page URL';
    throw new Error(
      `Refusing to ${stage} because the current page is ${currentSummary}, ` +
      `not ${requestedIdentity.origin} page ${requestedIdentity.pageId}.`
    );
  }
}

async function prepareConfluenceEditor() {
  const login = await loginState();
  if (login.maybe_login) {
    throw new Error(
      'Atlassian login is required for this persistent profile. ' +
      'Run `nix develop .#browser --command -- make atlassian-confluence-login`, ' +
      'complete the email verification in Chrome, then rerun the repro.'
    );
  }

  requireConfiguredPageIdentity('find or open an editor');

  let target = await findEditorTarget({ timeoutMilliseconds: 2500 });
  if (!target && editPage) {
    await clickEditButton();
    target = await findEditorTarget({ timeoutMilliseconds: editorTimeoutMilliseconds });
  }

  if (!target) {
    throw new Error(
      'Could not find a Confluence editor contenteditable target. ' +
      'Open the page in edit mode, set HISLE_ATLASSIAN_TARGET_SELECTOR, ' +
      'or rerun with HISLE_ATLASSIAN_EDIT=1.'
    );
  }

  requireConfiguredPageIdentity('instrument an editor for HID input');
  await installConfluenceInstrumentation(target);
}

async function loginState() {
  const currentURL = page.url();
  const title = await page.title().catch(() => '');
  const loginInputVisible = await firstVisibleElement([
    'input[type="email"]',
    'input[name="username"]',
    '#username',
    '[data-testid="username"]',
  ], 1000).then(Boolean).catch(() => false);

  return {
    url: currentURL,
    title,
    maybe_login: loginInputVisible ||
      /(^|\.)id\.atlassian\.com$/i.test(new URL(currentURL).hostname) ||
      /\/login\b/i.test(currentURL),
  };
}

async function clickEditButton() {
  const editButton = await firstVisibleElement([
    '[data-testid="edit-button"]',
    '[data-testid="ContentHeaderEditButton"]',
    'button[aria-label="Edit"]',
    'a[aria-label="Edit"]',
    'button[aria-label="편집"]',
    'a[aria-label="편집"]',
    'button:has-text("Edit")',
    'a:has-text("Edit")',
    'button:has-text("편집")',
    'a:has-text("편집")',
  ], 15000);

  if (!editButton) {
    return false;
  }

  requireConfiguredPageIdentity('click Edit');
  await editButton.click({ timeout: 10000 });
  await page.waitForLoadState('domcontentloaded', { timeout: 30000 }).catch(() => {});
  await page.waitForTimeout(2500);
  return true;
}

async function findEditorTarget({ timeoutMilliseconds }) {
  const started = Date.now();
  let lastError = null;

  while (Date.now() - started < timeoutMilliseconds) {
    try {
      const selectors = targetSelector
        ? [targetSelector]
        : [
            '.ProseMirror[contenteditable="true"]',
            '[data-testid="editor-content-area"] [contenteditable="true"]',
            '[data-testid="fabric-editor-popup-scroll-parent"] [contenteditable="true"]',
            'main [contenteditable="true"][role="textbox"]',
            'main [contenteditable="true"]',
            '[contenteditable="true"][role="textbox"]',
            '[contenteditable="true"]',
          ];

      for (const selector of selectors) {
        const handle = await firstUsableElement(selector);
        if (handle) {
          return handle;
        }
      }
    } catch (error) {
      lastError = error;
    }

    await page.waitForTimeout(500);
  }

  if (lastError) {
    consoleRecords.push({
      wall_clock_timestamp: new Date().toISOString(),
      type: 'target-search-error',
      text: String(lastError?.stack ?? lastError).slice(0, 4000),
      location: null,
    });
  }

  return null;
}

async function firstVisibleElement(selectors, timeoutMilliseconds) {
  const deadline = Date.now() + timeoutMilliseconds;

  while (Date.now() < deadline) {
    for (const selector of selectors) {
      const locator = page.locator(selector);
      const count = Math.min(await locator.count().catch(() => 0), 8);
      for (let index = 0; index < count; index += 1) {
        const item = locator.nth(index);
        if (await item.isVisible().catch(() => false)) {
          return item;
        }
      }
    }
    await page.waitForTimeout(250);
  }

  return null;
}

async function firstUsableElement(selector) {
  const handles = await page.$$(selector);
  for (const handle of handles) {
    const usable = await handle.evaluate((element) => {
      const rect = element.getBoundingClientRect();
      const style = window.getComputedStyle(element);
      const hidden = style.visibility === 'hidden' ||
        style.display === 'none' ||
        element.getAttribute('aria-hidden') === 'true';

      return !hidden &&
        rect.width >= 120 &&
        rect.height >= 30 &&
        rect.bottom > 0 &&
        rect.right > 0 &&
        rect.top < window.innerHeight &&
        rect.left < window.innerWidth;
    }).catch(() => false);

    if (usable) {
      return handle;
    }
  }

  return null;
}

async function installConfluenceInstrumentation(targetHandle) {
  await targetHandle.evaluate((element) => {
    element.scrollIntoView({ block: 'center', inline: 'nearest' });
  });
  await page.waitForTimeout(250);
  await page.evaluate(installDOMEventRecorder);

  await page.evaluate(({ target, expected, initialCaretOffset }) => {
    const eventTypes = [
      'pointerdown',
      'pointerup',
      'mousedown',
      'mouseup',
      'click',
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

    function targetRangeText() {
      const range = document.createRange();
      range.selectNodeContents(target);
      return range.toString();
    }

    function textNodeAndOffsetForTextOffset(root, desiredOffset) {
      const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
      let remaining = Math.max(0, desiredOffset);
      let lastTextNode = null;

      while (walker.nextNode()) {
        const node = walker.currentNode;
        lastTextNode = node;
        const length = node.nodeValue.length;
        if (remaining <= length) {
          return { node, offset: remaining };
        }
        remaining -= length;
      }

      if (lastTextNode) {
        return { node: lastTextNode, offset: lastTextNode.nodeValue.length };
      }

      return { node: root, offset: root.childNodes.length };
    }

    function caretOffsetForText(text, requestedOffset) {
      if (requestedOffset === 'middle') {
        return Math.floor(text.length / 2);
      }

      if (Number.isInteger(requestedOffset)) {
        return Math.min(Math.max(requestedOffset, 0), text.length);
      }

      return text.length;
    }

    function placeCaret() {
      target.focus({ preventScroll: true });
      const selection = window.getSelection();
      const text = targetRangeText();
      const offset = caretOffsetForText(text, initialCaretOffset);
      const position = textNodeAndOffsetForTextOffset(target, offset);
      const range = document.createRange();
      range.setStart(position.node, position.offset);
      range.collapse(true);
      selection.removeAllRanges();
      selection.addRange(range);
      return offset;
    }

    function caretClientPoint() {
      const selection = window.getSelection();
      if (selection && selection.rangeCount > 0) {
        const range = selection.getRangeAt(0).cloneRange();
        range.collapse(false);
        const rect = range.getBoundingClientRect();
        if (Number.isFinite(rect.left) && Number.isFinite(rect.top) && rect.height > 0) {
          return {
            x: rect.left + Math.max(1, Math.min(rect.width, 4)),
            y: rect.top + rect.height / 2,
            estimated: false,
          };
        }
      }

      const rect = target.getBoundingClientRect();
      return {
        x: rect.left + Math.min(Math.max(rect.width / 2, 24), 96),
        y: rect.top + Math.min(Math.max(rect.height / 2, 24), 96),
        estimated: true,
      };
    }

    function estimatedScreenPointForClientPoint(point) {
      if (!point) {
        return null;
      }
      const chromeLeftInset = (window.outerWidth - window.innerWidth) / 2;
      const chromeTopInset = window.outerHeight - window.innerHeight - chromeLeftInset;
      return {
        x: window.screenX + chromeLeftInset + point.x,
        y: window.screenY + chromeTopInset + point.y,
        estimated: point.estimated === true,
      };
    }

    if (window.__hisleAtlassian?.remove_listeners) {
      window.__hisleAtlassian.remove_listeners();
    }

    const initialText = target.innerText ?? target.textContent ?? '';
    const initialRangeText = targetRangeText();
    const initialCaretOffsetResolved = placeCaret();
    const clickPoint = caretClientPoint();
    const snapshotter = window.__hisleDOMEventRecorder.createTextSelectionSnapshotter(target, {
      contextRadius: 32,
    });
    const recorder = window.__hisleDOMEventRecorder.create({
      eventTypes,
      snapshot() {
        return snapshotter.snapshot();
      },
    });

    window.__hisleAtlassian = {
      target,
      expected_text: expected,
      initial_text: initialText,
      initial_range_text: initialRangeText,
      initial_caret_offset: initialCaretOffsetResolved,
      events: recorder.events,
      target_descriptor: window.__hisleDOMEventRecorder.elementIdentity(target),
      editor_click_client_point: clickPoint,
      editor_click_screen_point: estimatedScreenPointForClientPoint(clickPoint),
      viewport: {
        inner_width: window.innerWidth,
        inner_height: window.innerHeight,
        outer_width: window.outerWidth,
        outer_height: window.outerHeight,
        screen_x: window.screenX,
        screen_y: window.screenY,
      },
      remove_listeners() {
        recorder.stop();
        snapshotter.stop();
      },
    };

    recorder.start();

    window.__hisleAtlassian.ready = document.activeElement === target || target.contains(document.activeElement);
  }, {
    target: targetHandle,
    expected: expectedText,
    initialCaretOffset: initialCaretOffsetFromText(initialCaretOffsetText),
  });

  await page.waitForFunction(() => window.__hisleAtlassian?.ready === true, { timeout: 5000 });
  await page.bringToFront();
}

async function startServer() {
  server = await runtimeLifecycle.acquire(
    'observer-http-server',
    async () => {
      const acquiredServer = http.createServer((request, response) => {
        if (request.method === 'GET' && request.url === '/ready') {
          try {
            if (!loginOnly) {
              requireConfiguredPageIdentity('confirm readiness for the HID driver');
            }
            writeJSON(response, 200, { ok: true, runId, runDir });
          } catch (error) {
            writeJSON(response, 409, { ok: false, error: String(error?.stack ?? error) });
          }
          return;
        }

        if (request.method === 'POST' && request.url === '/place-caret') {
          placeConfiguredCaret()
            .then((result) => {
              writeJSON(response, 200, { ok: true, ...result });
            })
            .catch((error) => {
              writeJSON(response, 500, { ok: false, error: String(error?.stack ?? error) });
            });
          return;
        }

        if (request.method === 'POST' && request.url === '/finish') {
          readBody(request)
            .then((body) => {
              let payload = {};
              if (body.length > 0) {
                payload = JSON.parse(body);
              }
              requestObserverShutdown({
                reason: payload.reason ?? 'finish',
                driverExitCode: Number(payload.driver_exit_code ?? 0),
                response,
              });
            })
            .catch((error) => {
              writeJSON(response, 400, { ok: false, error: String(error?.stack ?? error) });
            });
          return;
        }

        writeJSON(response, 404, { ok: false, error: 'not found' });
      });

      await new Promise((resolve, reject) => {
        acquiredServer.once('error', reject);
        acquiredServer.listen(observerPort, '127.0.0.1', () => {
          acquiredServer.off('error', reject);
          resolve();
        });
      });
      return acquiredServer;
    },
    closeHttpServer,
  );
  throwIfShutdownRequested();
}

async function placeConfiguredCaret() {
  if (!page) {
    throw new Error('Cannot place caret before page is ready.');
  }

  requireConfiguredPageIdentity('place the editor caret for HID input');
  return page.evaluate(({ requestedOffset }) => {
    const state = window.__hisleAtlassian;
    const target = state?.target ?? null;
    if (!target) {
      throw new Error('Cannot place caret before Confluence instrumentation is installed.');
    }

    function targetText() {
      return target.innerText ?? target.textContent ?? '';
    }

    function targetRangeText() {
      const range = document.createRange();
      range.selectNodeContents(target);
      return range.toString();
    }

    function textNodeAndOffsetForTextOffset(root, desiredOffset) {
      const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
      let remaining = Math.max(0, desiredOffset);
      let lastTextNode = null;

      while (walker.nextNode()) {
        const node = walker.currentNode;
        lastTextNode = node;
        const length = node.nodeValue.length;
        if (remaining <= length) {
          return { node, offset: remaining };
        }
        remaining -= length;
      }

      if (lastTextNode) {
        return { node: lastTextNode, offset: lastTextNode.nodeValue.length };
      }

      return { node: root, offset: root.childNodes.length };
    }

    function caretOffsetForText(text, offset) {
      if (offset === 'middle') {
        return Math.floor(text.length / 2);
      }

      if (Number.isInteger(offset)) {
        return Math.min(Math.max(offset, 0), text.length);
      }

      return text.length;
    }

    function caretClientPoint() {
      const selection = window.getSelection();
      if (selection && selection.rangeCount > 0) {
        const range = selection.getRangeAt(0).cloneRange();
        range.collapse(false);
        const rect = range.getBoundingClientRect();
        if (Number.isFinite(rect.left) && Number.isFinite(rect.top) && rect.height > 0) {
          return {
            x: rect.left + Math.max(1, Math.min(rect.width, 4)),
            y: rect.top + rect.height / 2,
            estimated: false,
          };
        }
      }

      const rect = target.getBoundingClientRect();
      return {
        x: rect.left + Math.min(Math.max(rect.width / 2, 24), 96),
        y: rect.top + Math.min(Math.max(rect.height / 2, 24), 96),
        estimated: true,
      };
    }

    function estimatedScreenPointForClientPoint(point) {
      if (!point) {
        return null;
      }
      const chromeLeftInset = (window.outerWidth - window.innerWidth) / 2;
      const chromeTopInset = window.outerHeight - window.innerHeight - chromeLeftInset;
      return {
        x: window.screenX + chromeLeftInset + point.x,
        y: window.screenY + chromeTopInset + point.y,
        estimated: point.estimated === true,
      };
    }

    const text = targetRangeText();
    const visibleText = targetText();
    const offset = caretOffsetForText(text, requestedOffset);
    const position = textNodeAndOffsetForTextOffset(target, offset);
    target.focus({ preventScroll: true });

    const selection = window.getSelection();
    const range = document.createRange();
    range.setStart(position.node, position.offset);
    range.collapse(true);
    selection.removeAllRanges();
    selection.addRange(range);

    const clickPoint = caretClientPoint();
    state.initial_text = visibleText;
    state.initial_range_text = text;
    state.initial_caret_offset = offset;
    state.editor_click_client_point = clickPoint;
    state.editor_click_screen_point = estimatedScreenPointForClientPoint(clickPoint);

    return {
      initial_caret_offset: offset,
      initial_text_length: text.length,
      editor_click_client_point: state.editor_click_client_point,
      editor_click_screen_point: state.editor_click_screen_point,
    };
  }, { requestedOffset: initialCaretOffsetFromText(initialCaretOffsetText) });
}

async function writeReadyFile() {
  if (page && !loginOnly) {
    requireConfiguredPageIdentity('mark the observer ready for HID input');
  }

  const activeBrowser = browser ?? context.browser();
  const login = page ? await loginState().catch(() => null) : null;
  const editorState = page ? await page.evaluate(() => {
    const state = window.__hisleAtlassian;
    if (!state) {
      return null;
    }

    const text = state.target?.innerText ?? state.target?.textContent ?? '';
    const range = document.createRange();
    if (state.target) {
      range.selectNodeContents(state.target);
    }
    const rangeText = state.target ? range.toString() : '';
    return {
      initial_text: state.initial_text,
      initial_range_text: state.initial_range_text ?? null,
      current_text: text,
      current_range_text: rangeText,
      target_descriptor: state.target_descriptor,
      initial_caret_offset: state.initial_caret_offset ?? null,
      editor_click_client_point: state.editor_click_client_point,
      editor_click_screen_point: state.editor_click_screen_point,
      viewport: state.viewport,
      ready: state.ready === true,
    };
  }).catch(() => null) : null;
  const title = page ? await page.title().catch(() => '') : '';
  const windowTitleContains = configuredWindowTitleContains ||
    (title.toLowerCase().includes('confluence') ? 'Confluence' : title);
  const ready = {
    ok: true,
    run_id: runId,
    run_directory: runDir,
    observer_port: server.address().port,
    ready_wall_clock_timestamp: new Date().toISOString(),
    requested_page_url: requestedPageURL,
    current_page_url: page?.url() ?? null,
    profile_dir: profileDir,
    chrome_path: chromePath || null,
    chrome_version: activeBrowser ? activeBrowser.version() : null,
    remote_debugging_port: remoteDebuggingPort || null,
    normal_chrome: connectedToNormalChrome,
    reused_chrome: reuseNormalChrome,
    login_only: loginOnly,
    login_state: login,
    edit_page: editPage,
    target_selector: targetSelector || null,
    expected_text: expectedText,
    initial_caret_offset: editorState?.initial_caret_offset ?? null,
    window_title_contains: windowTitleContains || 'Confluence',
    editor_state: editorState,
    editor_click_client_point: editorState?.editor_click_client_point ?? null,
    editor_click_screen_point: editorState?.editor_click_screen_point ?? null,
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
  const domEvents = page ? await page.evaluate(() => {
    const instrumentation = window.__hisleAtlassian;
    const events = instrumentation?.events ?? [];
    instrumentation?.remove_listeners?.();
    return events;
  }).catch(() => []) : [];
  await writeJSONLines(path.join(runDir, 'dom-events.jsonl'), domEvents);
  await writeJSONLines(path.join(runDir, 'console.jsonl'), consoleRecords);

  const finalState = page ? await page.evaluate(() => {
    const state = window.__hisleAtlassian;
    const target = state?.target ?? null;
    const value = target ? (target.innerText ?? target.textContent ?? '') : '';
    const range = document.createRange();
    if (target) {
      range.selectNodeContents(target);
    }
    const rangeValue = target ? range.toString() : '';
    const initialText = state?.initial_text ?? '';
    const initialRangeText = state?.initial_range_text ?? initialText;
    const initialCaretOffset = state?.initial_caret_offset ?? null;
    const active = document.activeElement;

    return {
      wall_clock_timestamp: new Date().toISOString(),
      performance_now: performance.now(),
      value,
      range_value: rangeValue,
      initial_text: initialText,
      initial_range_text: initialRangeText,
      initial_caret_offset: initialCaretOffset,
      value_changed: rangeValue !== initialRangeText,
      active_element: active ? {
        tagName: active.tagName,
        id: active.id || null,
        role: active.getAttribute('role'),
        aria_label: active.getAttribute('aria-label'),
        data_testid: active.getAttribute('data-testid'),
      } : null,
      event_count: state?.events?.length ?? 0,
      composition_event_count: state?.events?.filter((event) => event.event_type.startsWith('composition')).length ?? 0,
      input_event_count: state?.events?.filter((event) => event.event_type === 'input').length ?? 0,
      beforeinput_event_count: state?.events?.filter((event) => event.event_type === 'beforeinput').length ?? 0,
      target_descriptor: state?.target_descriptor ?? null,
    };
  }).catch((error) => ({
    wall_clock_timestamp: new Date().toISOString(),
    value: '',
    range_value: '',
    initial_text: '',
    initial_range_text: '',
    initial_caret_offset: null,
    value_changed: false,
    event_count: 0,
    finalize_error: String(error?.stack ?? error),
  })) : {
    wall_clock_timestamp: new Date().toISOString(),
    value: '',
    range_value: '',
    initial_text: '',
    initial_range_text: '',
    initial_caret_offset: null,
    value_changed: false,
    event_count: 0,
  };

  Object.assign(finalState, {
    expected_text: expectedText,
    ...expectedDocumentState({
      initialRangeText: finalState.initial_range_text,
      initialCaretOffset: finalState.initial_caret_offset,
      expectedText,
      actualRangeText: finalState.range_value,
    }),
  });
  finalState.reason = reason;
  finalState.driver_exit_code = driverExitCode;
  finalState.matches_expected_text = driverExitCode === 0 &&
    finalState.value_changed === true &&
    finalState.matches_expected_full_text === true;
  finalState.anomalies = analyzeEvents(domEvents);

  await fs.writeFile(
    path.join(runDir, 'final-state.json'),
    `${JSON.stringify(finalState, null, 2)}\n`,
    'utf8',
  );

  if (page) {
    await page.screenshot({ path: path.join(runDir, 'screenshot.png'), fullPage: true }).catch(() => {});
  }

  const ok = loginOnly ||
    (driverExitCode === 0 && (allowMismatch || finalState.matches_expected_text === true));
  return {
    ok,
    reason,
    driver_exit_code: driverExitCode,
    allow_mismatch: allowMismatch,
    matches_expected_text: finalState.matches_expected_text,
    contains_expected_text: finalState.contains_expected_text,
    value_changed: finalState.value_changed,
    event_count: finalState.event_count,
  };
}

function analyzeEvents(events) {
  const focusLost = [];
  const emptyCompositionData = [];
  const jumpsWithoutValueChange = [];
  const regressions = [];
  let compositionEventCount = 0;
  let inputEventCount = 0;
  let previous = null;
  let maxSelection = null;

  for (const event of events) {
    if (event.event_type === 'blur') {
      focusLost.push(sampleEvent(event));
    }
    if (event.event_type.startsWith('composition')) {
      compositionEventCount += 1;
      if ((event.data ?? '') === '') {
        emptyCompositionData.push(sampleEvent(event));
      }
    }
    if (event.event_type === 'input') {
      inputEventCount += 1;
    }

    const selection = event.selection_start;
    const textLength = Number(event.editor_text_length ?? 0);
    if (typeof selection === 'number') {
      if (maxSelection != null && textLength >= (previous?.textLength ?? 0) && selection < maxSelection - 2) {
        regressions.push({
          ...sampleEvent(event),
          previous_max_selection: maxSelection,
        });
      }
      maxSelection = maxSelection == null ? selection : Math.max(maxSelection, selection);
    }

    if (
      previous &&
      typeof selection === 'number' &&
      typeof previous.selection === 'number' &&
      textLength === previous.textLength &&
      Math.abs(selection - previous.selection) > 1
    ) {
      jumpsWithoutValueChange.push({
        ...sampleEvent(event),
        previous_sequence: previous.sequence,
        previous_selection_start: previous.selection,
        delta: selection - previous.selection,
      });
    }

    previous = {
      sequence: event.sequence,
      selection,
      textLength,
    };
  }

  return {
    focus_lost_count: focusLost.length,
    composition_event_count: compositionEventCount,
    input_event_count: inputEventCount,
    empty_composition_data_count: emptyCompositionData.length,
    selection_jump_without_value_change_count: jumpsWithoutValueChange.length,
    selection_regression_count: regressions.length,
    focus_lost_samples: focusLost.slice(0, 12),
    empty_composition_data_samples: emptyCompositionData.slice(0, 12),
    selection_jump_without_value_change_samples: jumpsWithoutValueChange.slice(0, 12),
    selection_regression_samples: regressions.slice(0, 12),
  };
}

function sampleEvent(event) {
  return {
    sequence: event.sequence,
    event_type: event.event_type,
    key: event.key,
    data: event.data,
    input_type: event.input_type,
    is_composing: event.is_composing,
    editor_text_length: event.editor_text_length,
    selection_start: event.selection_start,
    selection_end: event.selection_end,
    active_element: event.active_element,
    event_target: event.event_target,
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
      expected_text: expectedText,
      matches_expected_text: false,
      setup_error: String(error?.stack ?? error),
    }, null, 2)}\n`,
    'utf8',
  );
}
