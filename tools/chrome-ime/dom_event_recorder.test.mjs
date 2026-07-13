import assert from 'node:assert/strict';
import process from 'node:process';
import test from 'node:test';

import { chromium } from 'playwright-core';

import { installDOMEventRecorder } from './dom_event_recorder.mjs';

test('records browser event payloads without page errors', { timeout: 30000 }, async (context) => {
  const launchOptions = {
    headless: true,
    args: ['--no-first-run', '--no-default-browser-check'],
  };
  if (process.env.CHROME_PATH) {
    launchOptions.executablePath = process.env.CHROME_PATH;
  } else {
    launchOptions.channel = 'chrome';
  }

  const browser = await chromium.launch(launchOptions);
  context.after(() => browser.close());

  const page = await browser.newPage();
  const pageErrors = [];
  page.on('pageerror', (error) => {
    pageErrors.push(String(error?.stack ?? error));
  });

  await page.setContent('<div id="target" contenteditable="true">x</div>');
  await page.evaluate(installDOMEventRecorder);
  const events = await page.evaluate(async () => {
    const target = document.getElementById('target');
    const recorder = window.__hisleDOMEventRecorder.create({
      eventTypes: [
        'keydown',
        'compositionstart',
        'compositionupdate',
        'compositionend',
        'beforeinput',
        'input',
        'selectionchange',
      ],
      snapshot() {
        const selection = window.getSelection();
        const range = selection?.rangeCount ? selection.getRangeAt(0) : null;
        return {
          value: target.textContent,
          selection_start: range?.startOffset ?? null,
          selection_end: range?.endOffset ?? null,
        };
      },
    });
    recorder.start();
    recorder.start();

    target.focus();
    target.dispatchEvent(new KeyboardEvent('keydown', {
      bubbles: true,
      code: 'KeyA',
      isComposing: true,
      key: 'a',
      repeat: true,
    }));
    target.dispatchEvent(new CompositionEvent('compositionstart', {
      bubbles: true,
      data: '\u3147',
    }));
    target.dispatchEvent(new CompositionEvent('compositionupdate', {
      bubbles: true,
      data: '\uc548',
    }));
    target.dispatchEvent(new InputEvent('beforeinput', {
      bubbles: true,
      data: '\uc548',
      inputType: 'insertCompositionText',
      isComposing: true,
    }));
    target.textContent = '\uc548';
    target.dispatchEvent(new InputEvent('input', {
      bubbles: true,
      data: '\uc548',
      inputType: 'insertCompositionText',
      isComposing: true,
    }));
    target.dispatchEvent(new CompositionEvent('compositionend', {
      bubbles: true,
      data: '\uc548',
    }));

    const selection = window.getSelection();
    const range = document.createRange();
    range.selectNodeContents(target);
    range.collapse(false);
    selection.removeAllRanges();
    selection.addRange(range);
    document.dispatchEvent(new Event('selectionchange'));

    await new Promise((resolve) => setTimeout(resolve, 0));
    recorder.stop();
    target.dispatchEvent(new KeyboardEvent('keydown', {
      bubbles: true,
      code: 'KeyB',
      key: 'b',
    }));
    return recorder.events;
  });
  await page.waitForTimeout(50);

  const keyboard = events.find((event) => event.event_type === 'keydown');
  assert.ok(keyboard);
  assert.equal(keyboard.key, 'a');
  assert.equal(keyboard.code, 'KeyA');
  assert.equal(keyboard.repeat, true);
  assert.equal(keyboard.is_composing, true);
  assert.equal(events.filter((event) => event.event_type === 'keydown').length, 1);

  for (const eventType of ['compositionstart', 'compositionupdate', 'compositionend']) {
    const composition = events.find((event) => event.event_type === eventType);
    assert.ok(composition);
    assert.equal(composition.data, eventType === 'compositionstart' ? '\u3147' : '\uc548');
  }

  for (const eventType of ['beforeinput', 'input']) {
    const input = events.find((event) => event.event_type === eventType);
    assert.ok(input);
    assert.equal(input.data, '\uc548');
    assert.equal(input.input_type, 'insertCompositionText');
    assert.equal(input.is_composing, true);
  }

  const selectionChange = events.find((event) => (
    event.event_type === 'selectionchange' && event.value === '\uc548'
  ));
  assert.ok(selectionChange);
  assert.equal(selectionChange.event_target.tagName, '#document');
  assert.equal(selectionChange.active_element.id, 'target');
  assert.equal(selectionChange.value, '\uc548');
  assert.equal(selectionChange.selection_start, 1);
  assert.equal(selectionChange.selection_end, 1);

  const snapshotContract = await page.evaluate(() => {
    document.body.innerHTML = '<div id="target" contenteditable="true">' +
      '<span id="left">abc</span><span id="middle">defghi</span><span id="right">jkl</span>' +
      '</div><div id="outside">outside</div>';
    const target = document.getElementById('target');
    const leftText = document.getElementById('left').firstChild;
    const middleText = document.getElementById('middle').firstChild;
    const rightText = document.getElementById('right').firstChild;
    const selection = window.getSelection();
    const range = document.createRange();
    range.setStart(middleText, 3);
    range.collapse(true);
    selection.removeAllRanges();
    selection.addRange(range);

    const snapshotter = window.__hisleDOMEventRecorder.createTextSelectionSnapshotter(target, {
      contextRadius: 3,
    });
    const initial = snapshotter.snapshot();

    leftText.nodeValue = 'ABCDE';
    const afterCharacterData = snapshotter.snapshot();

    const inserted = document.createElement('span');
    inserted.textContent = '12';
    target.insertBefore(inserted, document.getElementById('middle'));
    const afterChildInsert = snapshotter.snapshot();
    inserted.remove();
    const afterChildRemove = snapshotter.snapshot();

    const elementBoundary = document.createRange();
    elementBoundary.setStart(target, 2);
    elementBoundary.collapse(true);
    selection.removeAllRanges();
    selection.addRange(elementBoundary);
    const atElementBoundary = snapshotter.snapshot();

    selection.setBaseAndExtent(rightText, 2, middleText, 1);
    const backwardSelection = snapshotter.snapshot();

    const outsideText = document.getElementById('outside').firstChild;
    const outsideRange = document.createRange();
    outsideRange.setStart(outsideText, 1);
    outsideRange.collapse(true);
    selection.removeAllRanges();
    selection.addRange(outsideRange);
    const outsideSelection = snapshotter.snapshot();

    snapshotter.stop();
    snapshotter.stop();
    let stoppedError = null;
    try {
      snapshotter.snapshot();
    } catch (error) {
      stoppedError = String(error?.message ?? error);
    }

    return {
      initial,
      afterCharacterData,
      afterChildInsert,
      afterChildRemove,
      atElementBoundary,
      backwardSelection,
      outsideSelection,
      stoppedError,
    };
  });

  assert.deepEqual(snapshotContract.initial, {
    editor_text_length: 12,
    selection_start: 6,
    selection_end: 6,
    selection_anchor: 6,
    selection_focus: 6,
    caret_context: {
      before: 'def',
      after: 'ghi',
      before_truncated: true,
      after_truncated: true,
    },
  });
  assert.equal(Object.hasOwn(snapshotContract.initial, 'editor_text'), false);
  assert.equal(snapshotContract.afterCharacterData.editor_text_length, 14);
  assert.equal(snapshotContract.afterCharacterData.selection_focus, 8);
  assert.equal(snapshotContract.afterChildInsert.editor_text_length, 16);
  assert.equal(snapshotContract.afterChildInsert.selection_focus, 10);
  assert.equal(snapshotContract.afterChildRemove.editor_text_length, 14);
  assert.equal(snapshotContract.afterChildRemove.selection_focus, 8);
  assert.deepEqual(snapshotContract.atElementBoundary, {
    editor_text_length: 14,
    selection_start: 11,
    selection_end: 11,
    selection_anchor: 11,
    selection_focus: 11,
    caret_context: {
      before: 'ghi',
      after: 'jkl',
      before_truncated: true,
      after_truncated: false,
    },
  });
  assert.equal(snapshotContract.backwardSelection.selection_start, 6);
  assert.equal(snapshotContract.backwardSelection.selection_end, 13);
  assert.equal(snapshotContract.backwardSelection.selection_anchor, 13);
  assert.equal(snapshotContract.backwardSelection.selection_focus, 6);
  assert.deepEqual(snapshotContract.backwardSelection.caret_context, {
    before: 'DEd',
    after: 'efg',
    before_truncated: true,
    after_truncated: true,
  });
  assert.deepEqual(snapshotContract.outsideSelection, {
    editor_text_length: 14,
    selection_start: null,
    selection_end: null,
    selection_anchor: null,
    selection_focus: null,
    caret_context: null,
  });
  assert.equal(snapshotContract.stoppedError, 'Text selection snapshotter has been stopped.');
  assert.deepEqual(pageErrors, []);
});
