import { chromium } from 'playwright-core';
import { spawn } from 'node:child_process';
import http from 'node:http';
import fs from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';

import { installDOMEventRecorder } from './dom_event_recorder.mjs';
import {
  confluencePageIdentity,
  findPageWithConfluenceIdentity,
  hasSameConfluencePageIdentity,
} from './atlassian_page_identity.mjs';

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
const atlassianScenario = process.env.HISLE_ATLASSIAN_SCENARIO ?? 'annyeonghaseyo';
const defaultExpectedText = defaultExpectedTextForScenario(atlassianScenario);
const expectedText = nonEmptyEnv('HISLE_ATLASSIAN_EXPECTED_TEXT', defaultExpectedText);
const targetSelector = process.env.HISLE_ATLASSIAN_TARGET_SELECTOR ?? '';
const editPage = process.env.HISLE_ATLASSIAN_EDIT !== '0';
const loginOnly = process.env.HISLE_ATLASSIAN_LOGIN_ONLY === '1';
const keepOpen = process.env.HISLE_ATLASSIAN_KEEP_OPEN === '1';
const traceEnabled = process.env.HISLE_ATLASSIAN_TRACE !== '0';
const allowMismatch = process.env.HISLE_ATLASSIAN_ALLOW_MISMATCH === '1';
const editorTimeoutMilliseconds = numberFromEnv('HISLE_ATLASSIAN_EDITOR_TIMEOUT_MS', 90000);
const configuredWindowTitleContains = process.env.HISLE_ATLASSIAN_WINDOW_TITLE_CONTAINS ?? '';
const initialCaretOffsetText = process.env.HISLE_ATLASSIAN_INITIAL_CARET_OFFSET ?? '';
const strictFullText = initialCaretOffsetText !== '' || process.env.HISLE_ATLASSIAN_STRICT_FULL_TEXT === '1';
const readyFile = path.join(runDir, 'observer-ready.json');
const pidFile = path.join(runDir, 'observer.pid');

let context;
let browser;
let page;
let server;
let finalized = false;
let connectedToNormalChrome = false;
const consoleRecords = [];

await fs.mkdir(runDir, { recursive: true });
await fs.mkdir(profileDir, { recursive: true });
await fs.writeFile(pidFile, `${process.pid}\n`, 'utf8');

try {
  if (!loginOnly) {
    requiredRequestedPageIdentity();
  }
  await startBrowser();
  await startServer();

  if (!loginOnly) {
    await prepareConfluenceEditor();
  }

  await writeReadyFile();
  const mode = loginOnly ? 'login profile' : 'Confluence editor';
  console.log(`Atlassian observer ready for ${mode} on http://127.0.0.1:${server.address().port}`);

  if (loginOnly) {
    console.log(`Profile directory: ${profileDir}`);
    console.log('Complete the browser sign-in, then press Ctrl-C in this terminal to close the observer.');
  }
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
  finalize({ reason: 'sigint', driverExitCode: loginOnly ? 0 : 130 })
    .finally(() => process.exit(loginOnly ? 0 : 130));
});

function requiredEnv(name) {
  const value = process.env[name];
  if (!value) {
    throw new Error(`${name} is required`);
  }
  return value;
}

function nonEmptyEnv(name, fallback) {
  const value = process.env[name];
  return value && value.length > 0 ? value : fallback;
}

function numberFromEnv(name, fallback) {
  const text = process.env[name];
  if (!text) {
    return fallback;
  }
  const value = Number(text);
  return Number.isFinite(value) ? value : fallback;
}

function defaultExpectedTextForScenario(scenario) {
  switch (scenario) {
    case 'annyeong-space-backspace':
      return '안녕';
    case 'foo-bar-annyeong-space-backspace':
      return 'foo안녕 bar';
    default:
      return '안녕하세요';
  }
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

  context = await chromium.launchPersistentContext(profileDir, launchOptions);
  browser = context.browser();
  context.on('page', wirePage);

  if (traceEnabled) {
    await context.tracing.start({ screenshots: true, snapshots: true, sources: false });
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
    requestedPageURL,
  ];

  const cdpURL = `http://127.0.0.1:${remoteDebuggingPort}`;
  if (reuseNormalChrome) {
    await waitForCDP(cdpURL);
  } else {
    if (chromePath) {
      spawn(chromePath, chromeArgs, { detached: true, stdio: 'ignore' }).unref();
    } else {
      spawn('/usr/bin/open', ['-na', chromeApp, '--args', ...chromeArgs], { detached: true, stdio: 'ignore' }).unref();
    }

    await waitForCDP(cdpURL);
  }
  browser = await chromium.connectOverCDP(cdpURL);
  connectedToNormalChrome = true;
  context = browser.contexts()[0];
  if (!context) {
    throw new Error('Could not find the default Chrome context after connecting over CDP.');
  }
  context.on('page', wirePage);

  if (traceEnabled) {
    await context.tracing.start({ screenshots: true, snapshots: true, sources: false }).catch((error) => {
      consoleRecords.push({
        wall_clock_timestamp: new Date().toISOString(),
        type: 'trace-start-error',
        text: String(error?.stack ?? error).slice(0, 4000),
        location: null,
      });
    });
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

    function targetText() {
      return target.innerText ?? target.textContent ?? '';
    }

    function targetRangeText() {
      const range = document.createRange();
      range.selectNodeContents(target);
      return range.toString();
    }

    function textOffset(container, offset) {
      if (!container || !target.contains(container)) {
        return null;
      }

      const range = document.createRange();
      range.selectNodeContents(target);
      try {
        range.setEnd(container, offset);
      } catch {
        return null;
      }
      return range.toString().length;
    }

    function selectionState() {
      const selection = window.getSelection();
      if (!selection || selection.rangeCount === 0) {
        return {
          selection_start: null,
          selection_end: null,
          selection_anchor: null,
          selection_focus: null,
        };
      }

      const range = selection.getRangeAt(0);
      return {
        selection_start: textOffset(range.startContainer, range.startOffset),
        selection_end: textOffset(range.endContainer, range.endOffset),
        selection_anchor: textOffset(selection.anchorNode, selection.anchorOffset),
        selection_focus: textOffset(selection.focusNode, selection.focusOffset),
      };
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

    const initialText = targetText();
    const initialRangeText = targetRangeText();
    const initialCaretOffsetResolved = placeCaret();
    const clickPoint = caretClientPoint();
    const recorder = window.__hisleDOMEventRecorder.create({
      eventTypes,
      snapshot() {
        const state = selectionState();
        const text = targetText();
        return {
          editor_text: text,
          editor_text_length: text.length,
          selection_start: state.selection_start,
          selection_end: state.selection_end,
          selection_anchor: state.selection_anchor,
          selection_focus: state.selection_focus,
        };
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
  server = http.createServer((request, response) => {
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
  if (finalized) {
    return { ok: true, already_finalized: true };
  }
  finalized = true;

  const domEvents = page ? await page.evaluate(() => window.__hisleAtlassian?.events ?? []).catch(() => []) : [];
  await writeJSONLines(path.join(runDir, 'dom-events.jsonl'), domEvents);
  await writeJSONLines(path.join(runDir, 'console.jsonl'), consoleRecords);

  const finalState = page ? await page.evaluate(({ expected, strictFullText }) => {
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
    const expectedFullText = strictFullText && Number.isInteger(initialCaretOffset)
      ? initialRangeText.slice(0, initialCaretOffset) + expected + initialRangeText.slice(initialCaretOffset)
      : null;
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
      expected_text: expected,
      expected_full_text: expectedFullText,
      contains_expected_text: rangeValue.includes(expected),
      matches_expected_full_text: expectedFullText == null ? null : rangeValue === expectedFullText,
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
  }, { expected: expectedText, strictFullText }).catch((error) => ({
    wall_clock_timestamp: new Date().toISOString(),
    value: '',
    initial_text: '',
    value_changed: false,
    expected_text: expectedText,
    contains_expected_text: false,
    matches_expected_full_text: null,
    event_count: 0,
    finalize_error: String(error?.stack ?? error),
  })) : {
    wall_clock_timestamp: new Date().toISOString(),
    value: '',
    initial_text: '',
    value_changed: false,
    expected_text: expectedText,
    contains_expected_text: false,
    matches_expected_full_text: null,
    event_count: 0,
  };

  finalState.reason = reason;
  finalState.driver_exit_code = driverExitCode;
  const strictMatch = finalState.expected_full_text == null
    ? finalState.contains_expected_text
    : finalState.matches_expected_full_text;
  finalState.matches_expected_text = driverExitCode === 0 &&
    finalState.value_changed === true &&
    strictMatch === true;
  finalState.anomalies = analyzeEvents(domEvents);

  await fs.writeFile(
    path.join(runDir, 'final-state.json'),
    `${JSON.stringify(finalState, null, 2)}\n`,
    'utf8',
  );

  if (page) {
    await page.screenshot({ path: path.join(runDir, 'screenshot.png'), fullPage: true }).catch(() => {});
  }

  if (traceEnabled && context) {
    await context.tracing.stop({ path: path.join(runDir, 'trace.zip') }).catch(() => {});
  }

  if (!keepOpen) {
    if (connectedToNormalChrome && browser) {
      await browser.close().catch(() => {});
    } else if (context) {
      await context.close().catch(() => {});
    }
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
    const textLength = Number(event.editor_text_length ?? String(event.editor_text ?? '').length);
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
