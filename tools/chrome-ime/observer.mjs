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
const targetKind = process.env.HISLE_CHROME_TARGET ?? 'textarea';
const initialText = process.env.HISLE_CHROME_INITIAL_TEXT ?? '';
const initialCaretText = process.env.HISLE_CHROME_INITIAL_CARET ?? '';
const initialSelectionText = process.env.HISLE_CHROME_INITIAL_SELECTION ?? '';
const initialDoubleClick = process.env.HISLE_CHROME_INITIAL_DOUBLE_CLICK === '1';
const initialRender = nonEmptyEnv('HISLE_CHROME_INITIAL_RENDER', 'text');
const moveAfterCompositionCaretText = process.env.HISLE_CHROME_MOVE_AFTER_COMPOSITION_CARET ?? '';
const moveAfterInputCaretText = process.env.HISLE_CHROME_MOVE_AFTER_INPUT_CARET ?? '';
const clickAfterInputCaretText = process.env.HISLE_CHROME_CLICK_AFTER_INPUT_CARET ?? '';
const dragSelectionText = process.env.HISLE_CHROME_DRAG_SELECTION ?? '';
const forceRenderOnCompositionEnd = process.env.HISLE_CHROME_FORCE_RENDER_ON_COMPOSITION_END === '1';
const editorChaos = process.env.HISLE_CHROME_EDITOR_CHAOS ?? '';
const chaosDelayMilliseconds = numberFromEnv('HISLE_CHROME_CHAOS_DELAY_MS', 650);
const keepOpen = process.env.HISLE_CHROME_KEEP_OPEN === '1';
const traceEnabled = process.env.HISLE_CHROME_TRACE !== '0';
const allowMismatch = process.env.HISLE_CHROME_ALLOW_MISMATCH === '1';
const expectedUnit = 'f`\u{C758}f\u{C5B4}\u{315C}f';
const expectedValue = process.env.EXPECTED_VALUE && process.env.EXPECTED_VALUE.length > 0
  ? process.env.EXPECTED_VALUE
  : expectedUnit.repeat(iterations);
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
  if (!['textarea', 'contenteditable', 'wysiwyg'].includes(targetKind)) {
    throw new Error(`Unsupported HISLE_CHROME_TARGET: ${targetKind}`);
  }
  if (!['text', 'spans', 'paragraphs'].includes(initialRender)) {
    throw new Error(`Unsupported HISLE_CHROME_INITIAL_RENDER: ${initialRender}`);
  }
  if (!['', 'idle-normalize', 'focus-pulse', 'active-rerender', 'active-rerender-focus-pulse', 'restore-initial-selection'].includes(editorChaos)) {
    throw new Error(`Unsupported HISLE_CHROME_EDITOR_CHAOS: ${editorChaos}`);
  }
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
  const isTextarea = targetKind === 'textarea';
  const isWysiwyg = targetKind === 'wysiwyg';
  const targetMarkup = isTextarea
    ? '<textarea id="target" class="input-surface" autofocus spellcheck="false" autocapitalize="off" autocomplete="off"></textarea>'
    : `<div id="target" class="input-surface editable${isWysiwyg ? ' wysiwyg' : ''}" contenteditable="true" role="textbox" aria-label="hisle Chrome IME Repro" spellcheck="false" autocapitalize="off" autocomplete="off"></div>`;

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

    .input-surface {
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
      white-space: pre-wrap;
      overflow-wrap: break-word;
    }

    .input-surface:focus {
      border-color: #0f766e;
      box-shadow: 0 0 0 4px rgba(15, 118, 110, 0.18);
    }

    .editable:empty::before {
      content: attr(data-placeholder);
      color: #9ca3af;
    }

    .wysiwyg {
      font-family: "Apple SD Gothic Neo", "Noto Sans CJK KR", ui-sans-serif, system-ui, sans-serif;
    }

    .wysiwyg span {
      border-radius: 3px;
    }

    .wysiwyg p {
      margin: 0;
      min-height: 1.45em;
    }
  </style>
</head>
<body>
  <main>
    <h1>hisle Chrome IME Repro - ${targetKind}</h1>
    ${targetMarkup}
  </main>
</body>
</html>`);

  await targetPage.evaluate(({
    kind,
    initialText,
    initialCaretText,
    initialSelectionText,
    initialRender,
    moveAfterCompositionCaretText,
    moveAfterInputCaretText,
    clickAfterInputCaretText,
    dragSelectionText,
    forceRenderOnCompositionEnd,
    editorChaos,
    chaosDelayMilliseconds,
  }) => {
    const target = document.getElementById('target');
    const isTextarea = target instanceof HTMLTextAreaElement;
    const isWysiwyg = kind === 'wysiwyg';
    const initialCaret = initialCaretText === '' ? null : Number(initialCaretText);
    const initialSelection = parseOffsetRange(initialSelectionText);
    const moveAfterCompositionCaret = moveAfterCompositionCaretText === '' ? null : Number(moveAfterCompositionCaretText);
    const moveAfterInputCaret = moveAfterInputCaretText === '' ? null : Number(moveAfterInputCaretText);
    const clickAfterInputCaret = clickAfterInputCaretText === '' ? null : Number(clickAfterInputCaretText);
    const dragSelection = parseOffsetRange(dragSelectionText);
    let idleTimer = null;
    let compositionEndCount = 0;
    let inputCount = 0;
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

    window.__hisleEvents = [];
    window.__hisleChaosEvents = [];
    window.__hisleEventSequence = 0;

    target.dataset.placeholder = kind;
    if (initialText) {
      if (isTextarea) {
        target.value = initialText;
        target.setSelectionRange(initialText.length, initialText.length);
      } else {
        target.textContent = initialText;
      }
    }

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

    function targetValue() {
      if (!isTextarea && initialRender === 'paragraphs') {
        const lines = Array.from(target.querySelectorAll('[data-line]'));
        if (lines.length > 0) {
          return lines.map((line) => line.textContent ?? '').join('\n');
        }
      }
      return isTextarea ? target.value : target.textContent ?? '';
    }

    function parseOffsetRange(text) {
      if (!text) {
        return null;
      }

      const parts = text.split(':');
      if (parts.length !== 2) {
        throw new Error(`HISLE_CHROME_DRAG_SELECTION must use start:end syntax, got ${text}`);
      }

      const start = Number(parts[0]);
      const end = Number(parts[1]);
      if (!Number.isFinite(start) || !Number.isFinite(end)) {
        throw new Error(`HISLE_CHROME_DRAG_SELECTION offsets must be finite numbers, got ${text}`);
      }

      return { start, end };
    }

    function textOffset(container, offset) {
      if (!container || !target.contains(container)) {
        return null;
      }

      if (!isTextarea && initialRender === 'paragraphs') {
        let logicalOffset = 0;
        const lines = Array.from(target.querySelectorAll('[data-line]'));
        for (const [lineIndex, line] of lines.entries()) {
          const walker = document.createTreeWalker(line, NodeFilter.SHOW_TEXT);
          let node = walker.nextNode();
          while (node) {
            if (node === container) {
              return logicalOffset + offset;
            }
            logicalOffset += node.data.length;
            node = walker.nextNode();
          }

          if (container === line) {
            return logicalOffset;
          }

          if (lineIndex < lines.length - 1) {
            logicalOffset += 1;
          }
        }
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
      if (isTextarea) {
        return {
          selection_start: target.selectionStart,
          selection_end: target.selectionEnd,
          selection_anchor: target.selectionStart,
          selection_focus: target.selectionEnd,
        };
      }

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
      const start = textOffset(range.startContainer, range.startOffset);
      const end = textOffset(range.endContainer, range.endOffset);

      return {
        selection_start: start,
        selection_end: end,
        selection_anchor: textOffset(selection.anchorNode, selection.anchorOffset),
        selection_focus: textOffset(selection.focusNode, selection.focusOffset),
      };
    }

    function recordChaos(action, extra = {}) {
      const selection = selectionState();
      window.__hisleChaosEvents.push({
        sequence: window.__hisleChaosEvents.length + 1,
        wall_clock_timestamp: new Date().toISOString(),
        performance_now: performance.now(),
        action,
        composing: target.dataset.composing === '1',
        value: targetValue(),
        selection_start: selection.selection_start,
        selection_end: selection.selection_end,
        active_element: activeElementIdentity(),
        ...extra,
      });
    }

    function textLocationForOffset(offset) {
      const bounded = Math.max(0, Math.min(offset, targetValue().length));

      if (initialRender === 'paragraphs') {
        let remaining = bounded;
        const lines = Array.from(target.querySelectorAll('[data-line]'));
        for (const [lineIndex, line] of lines.entries()) {
          const lineText = line.textContent ?? '';
          if (remaining <= lineText.length) {
            const walker = document.createTreeWalker(line, NodeFilter.SHOW_TEXT);
            let textRemaining = remaining;
            let node = walker.nextNode();
            while (node) {
              if (textRemaining <= node.data.length) {
                return { node, offset: textRemaining };
              }
              textRemaining -= node.data.length;
              node = walker.nextNode();
            }
            return { node: line, offset: line.childNodes.length };
          }

          remaining -= lineText.length;
          if (lineIndex < lines.length - 1) {
            if (remaining === 0) {
              return { node: line, offset: line.childNodes.length };
            }
            remaining -= 1;
          }
        }
      }

      const walker = document.createTreeWalker(target, NodeFilter.SHOW_TEXT);
      let remaining = bounded;
      let node = walker.nextNode();
      while (node) {
        if (remaining <= node.data.length) {
          return { node, offset: remaining };
        }
        remaining -= node.data.length;
        node = walker.nextNode();
      }

      return { node: target, offset: target.childNodes.length };
    }

    function setTextSelectionByOffset(offset) {
      if (isTextarea) {
        const bounded = Math.max(0, Math.min(offset, target.value.length));
        target.setSelectionRange(bounded, bounded);
        return true;
      }

      const selection = window.getSelection();
      const range = document.createRange();
      const location = textLocationForOffset(offset);
      range.setStart(location.node, location.offset);
      range.collapse(true);
      selection.removeAllRanges();
      selection.addRange(range);
      return true;
    }

    function setTextSelectionRangeByOffset(start, end) {
      if (isTextarea) {
        const boundedStart = Math.max(0, Math.min(start, target.value.length));
        const boundedEnd = Math.max(0, Math.min(end, target.value.length));
        target.setSelectionRange(boundedStart, boundedEnd);
        return true;
      }

      const boundedStart = Math.max(0, Math.min(start, targetValue().length));
      const boundedEnd = Math.max(0, Math.min(end, targetValue().length));
      const selectionStart = Math.min(boundedStart, boundedEnd);
      const selectionEnd = Math.max(boundedStart, boundedEnd);
      const startLocation = textLocationForOffset(selectionStart);
      const endLocation = textLocationForOffset(selectionEnd);
      const selection = window.getSelection();
      const range = document.createRange();
      range.setStart(startLocation.node, startLocation.offset);
      range.setEnd(endLocation.node, endLocation.offset);
      selection.removeAllRanges();
      selection.addRange(range);
      return true;
    }

    function textPositionForOffset(offset) {
      const bounded = Math.max(0, Math.min(offset, targetValue().length));
      if (isTextarea) {
        const rect = target.getBoundingClientRect();
        const style = window.getComputedStyle(target);
        const paddingLeft = Number.parseFloat(style.paddingLeft) || 0;
        const paddingTop = Number.parseFloat(style.paddingTop) || 0;
        const fontSize = Number.parseFloat(style.fontSize) || 28;
        const lineHeight = Number.parseFloat(style.lineHeight) || fontSize * 1.45;
        const canvas = textPositionForOffset.canvas ?? document.createElement('canvas');
        textPositionForOffset.canvas = canvas;
        const context = canvas.getContext('2d');
        const before = target.value.slice(0, bounded);
        const lines = before.split('\n');
        const lineText = lines.at(-1) ?? '';
        context.font = style.font || `${style.fontSize} ${style.fontFamily}`;

        return {
          x: rect.left + paddingLeft + context.measureText(lineText).width - target.scrollLeft,
          y: rect.top + paddingTop + ((lines.length - 1) * lineHeight) + (lineHeight / 2) - target.scrollTop,
          offset: bounded,
          estimated: false,
        };
      }

      const walker = document.createTreeWalker(target, NodeFilter.SHOW_TEXT);
      let remaining = bounded;
      let node = walker.nextNode();
      let previousTextNode = null;
      while (node) {
        if (remaining <= node.data.length) {
          const range = document.createRange();
          const start = Math.min(remaining, Math.max(0, node.data.length - 1));
          const end = Math.min(node.data.length, start + 1);
          range.setStart(node, start);
          range.setEnd(node, end);
          const rect = range.getBoundingClientRect();
          return {
            x: rect.left + 1,
            y: rect.top + rect.height / 2,
            offset: bounded,
            estimated: false,
          };
        }
        remaining -= node.data.length;
        previousTextNode = node;
        node = walker.nextNode();
      }

      if (previousTextNode) {
        const range = document.createRange();
        const start = Math.max(0, previousTextNode.data.length - 1);
        range.setStart(previousTextNode, start);
        range.setEnd(previousTextNode, previousTextNode.data.length);
        const rect = range.getBoundingClientRect();
        return {
          x: rect.right + 1,
          y: rect.top + rect.height / 2,
          offset: bounded,
          estimated: false,
        };
      }

      const rect = target.getBoundingClientRect();
      return {
        x: rect.left + 24,
        y: rect.top + 24,
        offset: bounded,
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
      };
    }

    function rerenderWysiwygDOM({ allowDuringComposition = false, force = false } = {}) {
      if (!isWysiwyg || (!allowDuringComposition && target.dataset.composing === '1')) {
        return;
      }

      const value = targetValue();
      if (value === '' || (!force && target.childElementCount > 0)) {
        return;
      }

      const selection = window.getSelection();
      const caretOffset = selection?.rangeCount ? textOffset(selection.focusNode, selection.focusOffset) : value.length;
      if (initialRender === 'paragraphs') {
        renderParagraphDOM(value);
        if (caretOffset != null) {
          setTextSelectionByOffset(caretOffset);
        }
        return;
      }

      const fragment = document.createDocumentFragment();

      for (const character of value) {
        const span = document.createElement('span');
        span.textContent = character;
        fragment.appendChild(span);
      }

      target.replaceChildren(fragment);
      if (caretOffset != null) {
        setTextSelectionByOffset(caretOffset);
      }
    }

    function renderParagraphDOM(value) {
      const fragment = document.createDocumentFragment();
      for (const line of value.split('\n')) {
        const paragraph = document.createElement('p');
        paragraph.dataset.line = '1';
        if (line.length === 0) {
          paragraph.appendChild(document.createElement('br'));
        } else {
          for (const character of line) {
            const span = document.createElement('span');
            span.textContent = character;
            paragraph.appendChild(span);
          }
        }
        fragment.appendChild(paragraph);
      }
      target.replaceChildren(fragment);
    }

    function idleEditorMaintenance() {
      if (!editorChaos || (target.dataset.composing === '1' && !editorChaos.startsWith('active-rerender'))) {
        return;
      }

      const before = selectionState();
      recordChaos('idle-before');

      if (editorChaos === 'idle-normalize') {
        rerenderWysiwygDOM();
        if (before.selection_focus != null) {
          setTextSelectionByOffset(before.selection_focus);
        }
      } else if (editorChaos === 'focus-pulse') {
        target.blur();
        recordChaos('focus-pulse-blur');
        target.focus();
        if (before.selection_focus != null) {
          setTextSelectionByOffset(before.selection_focus);
        }
      } else if (editorChaos === 'active-rerender') {
        rerenderWysiwygDOM({ allowDuringComposition: true, force: true });
        if (before.selection_focus != null) {
          setTextSelectionByOffset(before.selection_focus);
        }
      } else if (editorChaos === 'active-rerender-focus-pulse') {
        rerenderWysiwygDOM({ allowDuringComposition: true, force: true });
        target.blur();
        recordChaos('active-rerender-focus-pulse-blur');
        target.focus();
        if (before.selection_focus != null) {
          setTextSelectionByOffset(before.selection_focus);
        }
      }

      recordChaos('idle-after', {
        before_selection_start: before.selection_start,
        before_selection_end: before.selection_end,
      });
    }

    function scheduleIdleMaintenance() {
      if (!editorChaos) {
        return;
      }

      clearTimeout(idleTimer);
      idleTimer = setTimeout(idleEditorMaintenance, chaosDelayMilliseconds);
    }

    function record(event) {
      const eventTimestamp = Number(event.timeStamp ?? performance.now());
      const wallClockTimestamp = new Date(performance.timeOrigin + eventTimestamp).toISOString();
      const selection = selectionState();

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
        value: targetValue(),
        selection_start: selection.selection_start,
        selection_end: selection.selection_end,
        selection_anchor: selection.selection_anchor,
        selection_focus: selection.selection_focus,
        active_element: activeElementIdentity(),
      });

      if (event.type === 'input' || event.type === 'compositionupdate' || event.type === 'compositionend') {
        scheduleIdleMaintenance();
      }
    }

    for (const type of eventTypes) {
      document.addEventListener(type, record, { capture: true });
    }

    if (initialRender === 'spans') {
      rerenderWysiwygDOM({ force: true });
    } else if (initialRender === 'paragraphs') {
      renderParagraphDOM(targetValue());
    }

    target.addEventListener('compositionstart', () => {
      target.dataset.composing = '1';
    });
    target.addEventListener('compositionend', () => {
      target.dataset.composing = '0';
      rerenderWysiwygDOM({ force: forceRenderOnCompositionEnd });
      compositionEndCount += 1;
      if (editorChaos === 'restore-initial-selection' && initialSelection != null) {
        setTextSelectionRangeByOffset(initialSelection.start, initialSelection.end);
        recordChaos('restore-initial-selection', {
          target_selection_start: initialSelection.start,
          target_selection_end: initialSelection.end,
          composition_end_count: compositionEndCount,
        });
      }
      if (compositionEndCount === 1 &&
          moveAfterCompositionCaret != null &&
          Number.isFinite(moveAfterCompositionCaret)) {
        setTimeout(() => {
          setTextSelectionByOffset(moveAfterCompositionCaret);
          recordChaos('move-after-composition', {
            target_selection_offset: moveAfterCompositionCaret,
            composition_end_count: compositionEndCount,
          });
        }, 50);
      }
    });
    target.addEventListener('input', () => rerenderWysiwygDOM());
    target.addEventListener('input', () => {
      inputCount += 1;
      if (inputCount === 1 &&
          moveAfterInputCaret != null &&
          Number.isFinite(moveAfterInputCaret)) {
        setTimeout(() => {
          setTextSelectionByOffset(moveAfterInputCaret);
          recordChaos('move-after-input', {
            target_selection_offset: moveAfterInputCaret,
            input_count: inputCount,
            composing: target.dataset.composing === '1',
          });
        }, 50);
      }
    });

    target.focus();
    if (initialSelection != null) {
      setTextSelectionRangeByOffset(initialSelection.start, initialSelection.end);
    } else if (initialCaret != null && Number.isFinite(initialCaret)) {
      setTextSelectionByOffset(initialCaret);
    } else if (!isTextarea && initialText) {
      const selection = window.getSelection();
      const range = document.createRange();
      range.selectNodeContents(target);
      range.collapse(false);
      selection.removeAllRanges();
      selection.addRange(range);
    }
    const selection = selectionState();
    const caretClientPoint = textPositionForOffset(selection.selection_focus ?? targetValue().length);
    const clickAfterInputClientPoint = clickAfterInputCaret != null && Number.isFinite(clickAfterInputCaret)
      ? textPositionForOffset(clickAfterInputCaret)
      : null;
    const dragSelectionStartClientPoint = dragSelection ? textPositionForOffset(dragSelection.start) : null;
    const dragSelectionEndClientPoint = dragSelection ? textPositionForOffset(dragSelection.end) : null;
    window.__hisleInitialState = {
      value: targetValue(),
      html: isTextarea ? null : target.innerHTML,
      initial_selection: initialSelection,
      selection_start: selection.selection_start,
      selection_end: selection.selection_end,
      selection_anchor: selection.selection_anchor,
      selection_focus: selection.selection_focus,
      active_element: activeElementIdentity(),
      viewport: {
        inner_width: window.innerWidth,
        inner_height: window.innerHeight,
        outer_width: window.outerWidth,
        outer_height: window.outerHeight,
        screen_x: window.screenX,
        screen_y: window.screenY,
      },
      caret_client_point: caretClientPoint,
      estimated_screen_point: estimatedScreenPointForClientPoint(caretClientPoint),
      click_after_input_client_point: clickAfterInputClientPoint,
      click_after_input_screen_point: estimatedScreenPointForClientPoint(clickAfterInputClientPoint),
      drag_selection: dragSelection,
      drag_selection_start_client_point: dragSelectionStartClientPoint,
      drag_selection_end_client_point: dragSelectionEndClientPoint,
      drag_selection_start_screen_point: estimatedScreenPointForClientPoint(dragSelectionStartClientPoint),
      drag_selection_end_screen_point: estimatedScreenPointForClientPoint(dragSelectionEndClientPoint),
    };
    window.__hisleReady = document.activeElement === target;
  }, {
    kind: targetKind,
    initialText,
    initialCaretText,
    initialSelectionText,
    initialRender,
    moveAfterCompositionCaretText,
    moveAfterInputCaretText,
    clickAfterInputCaretText,
    dragSelectionText,
    forceRenderOnCompositionEnd,
    editorChaos,
    chaosDelayMilliseconds,
  });

  await targetPage.waitForFunction(() => window.__hisleReady === true);
  if (initialDoubleClick) {
    const point = await targetPage.evaluate(() => window.__hisleInitialState?.caret_client_point ?? null);
    if (!point) {
      throw new Error('HISLE_CHROME_INITIAL_DOUBLE_CLICK requires a resolvable initial caret point.');
    }

    await targetPage.mouse.dblclick(point.x, point.y);
    await targetPage.waitForTimeout(150);
    await targetPage.evaluate(() => {
      const target = document.getElementById('target');
      const isTextarea = target instanceof HTMLTextAreaElement;

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
        if (isTextarea) {
          return {
            selection_start: target.selectionStart,
            selection_end: target.selectionEnd,
            selection_anchor: target.selectionStart,
            selection_focus: target.selectionEnd,
          };
        }

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

      const selection = selectionState();
      window.__hisleInitialState = {
        ...window.__hisleInitialState,
        value: isTextarea ? target.value : target.textContent ?? '',
        html: isTextarea ? null : target.innerHTML,
        double_clicked: true,
        selection_start: selection.selection_start,
        selection_end: selection.selection_end,
        selection_anchor: selection.selection_anchor,
        selection_focus: selection.selection_focus,
      };
    });
  }
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
  const initialState = page ? await page.evaluate(() => window.__hisleInitialState ?? null) : null;
  const ready = {
    ok: true,
    run_id: runId,
    run_directory: runDir,
    observer_port: server.address().port,
    ready_wall_clock_timestamp: new Date().toISOString(),
    chrome_path: chromePath || null,
    chrome_version: browser ? browser.version() : null,
    remote_debugging_port: remoteDebuggingPort || null,
    target_kind: targetKind,
    initial_text: initialText,
    initial_caret: initialCaretText || null,
    initial_selection: initialSelectionText || null,
    initial_double_click: initialDoubleClick,
    initial_render: initialRender,
    move_after_composition_caret: moveAfterCompositionCaretText || null,
    move_after_input_caret: moveAfterInputCaretText || null,
    drag_selection: dragSelectionText || null,
    force_render_on_composition_end: forceRenderOnCompositionEnd,
    editor_chaos: editorChaos || null,
    chaos_delay_milliseconds: chaosDelayMilliseconds,
    initial_state: initialState,
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
  const chaosEvents = page ? await page.evaluate(() => window.__hisleChaosEvents ?? []) : [];
  await writeJSONLines(path.join(runDir, 'editor-chaos.jsonl'), chaosEvents);

  const finalState = page ? await page.evaluate(({ expected, initialRender }) => {
    const target = document.getElementById('target');
    const isTextarea = target instanceof HTMLTextAreaElement;
    const active = document.activeElement;
    const activeElement = active ? {
      tagName: active.tagName,
      id: active.id || null,
      name: active.getAttribute('name'),
    } : null;

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
      if (isTextarea) {
        return {
          selection_start: target.selectionStart,
          selection_end: target.selectionEnd,
        };
      }

      const selection = window.getSelection();
      if (!selection || selection.rangeCount === 0) {
        return {
          selection_start: null,
          selection_end: null,
        };
      }

      const range = selection.getRangeAt(0);
      return {
        selection_start: textOffset(range.startContainer, range.startOffset),
        selection_end: textOffset(range.endContainer, range.endOffset),
      };
    }

    function targetValue() {
      if (!isTextarea && initialRender === 'paragraphs') {
        const lines = Array.from(target.querySelectorAll('[data-line]'));
        if (lines.length > 0) {
          return lines.map((line) => line.textContent ?? '').join('\n');
        }
      }
      return isTextarea ? target.value : target.textContent ?? '';
    }

    const selection = selectionState();
    const value = targetValue();

    return {
      wall_clock_timestamp: new Date().toISOString(),
      performance_now: performance.now(),
      value,
      html: isTextarea ? null : target.innerHTML,
      selection_start: selection.selection_start,
      selection_end: selection.selection_end,
      active_element: activeElement,
      event_count: window.__hisleEvents?.length ?? 0,
      chaos_event_count: window.__hisleChaosEvents?.length ?? 0,
      expected_value: expected,
      matches_expected_value: value === expected,
    };
  }, { expected: expectedValue, initialRender }) : {
    wall_clock_timestamp: new Date().toISOString(),
    value: '',
    expected_value: expectedValue,
    matches_expected_value: false,
  };

  finalState.reason = reason;
  finalState.driver_exit_code = driverExitCode;
  finalState.anomalies = analyzeEvents(domEvents);

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
  const effectiveOk = driverExitCode === 0 && (allowMismatch || finalState.matches_expected_value === true);
  return {
    ok: effectiveOk,
    reason,
    driver_exit_code: driverExitCode,
    allow_mismatch: allowMismatch,
    matches_expected_value: finalState.matches_expected_value,
    value: finalState.value,
    expected_value: expectedValue,
    event_count: finalState.event_count,
  };
}

function analyzeEvents(events) {
  const focusLost = [];
  const nullSelections = [];
  const jumpsWithoutValueChange = [];
  const regressions = [];
  let previous = null;
  let maxSelection = null;

  for (const event of events) {
    const activeID = event.active_element?.id ?? null;
    if (event.event_type === 'blur' || (event.active_element && activeID !== 'target')) {
      focusLost.push(sampleEvent(event));
    }

    if (event.selection_start == null || event.selection_end == null) {
      nullSelections.push(sampleEvent(event));
    }

    const selection = event.selection_start;
    const valueLength = String(event.value ?? '').length;
    if (typeof selection === 'number') {
      if (maxSelection != null && valueLength >= (previous?.valueLength ?? 0) && selection < maxSelection - 2) {
        regressions.push({
          ...sampleEvent(event),
          previous_max_selection: maxSelection,
        });
      }
      maxSelection = maxSelection == null ? selection : Math.max(maxSelection, selection);
    }

    if (
      previous &&
      event.event_type === 'selectionchange' &&
      typeof selection === 'number' &&
      typeof previous.selection === 'number' &&
      valueLength === previous.valueLength &&
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
      valueLength,
    };
  }

  return {
    focus_lost_count: focusLost.length,
    null_selection_count: nullSelections.length,
    selection_jump_without_value_change_count: jumpsWithoutValueChange.length,
    selection_regression_count: regressions.length,
    focus_lost_samples: focusLost.slice(0, 12),
    null_selection_samples: nullSelections.slice(0, 12),
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
    value_length: String(event.value ?? '').length,
    selection_start: event.selection_start,
    selection_end: event.selection_end,
    active_element: event.active_element,
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
