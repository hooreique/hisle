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
  assert.deepEqual(pageErrors, []);
});
