export function installDOMEventRecorder() {
  const maximumContextRadius = 64;

  function eventValue(event, key) {
    return key in event ? event[key] : null;
  }

  function elementIdentity(element) {
    if (!element) {
      return null;
    }

    const isElement = element instanceof Element;
    return {
      tagName: isElement ? element.tagName : (element.nodeName ?? null),
      id: isElement ? (element.id || null) : null,
      name: isElement ? element.getAttribute('name') : null,
      role: isElement ? element.getAttribute('role') : null,
      aria_label: isElement ? element.getAttribute('aria-label') : null,
      data_testid: isElement ? element.getAttribute('data-testid') : null,
      class_name: isElement && typeof element.className === 'string'
        ? element.className.slice(0, 240)
        : null,
    };
  }

  function serializeEvent(event) {
    const eventTimestamp = Number(event.timeStamp ?? performance.now());
    return {
      performance_now: performance.now(),
      event_timestamp: eventTimestamp,
      wall_clock_timestamp: new Date(performance.timeOrigin + eventTimestamp).toISOString(),
      event_type: event.type,
      key: eventValue(event, 'key'),
      code: eventValue(event, 'code'),
      repeat: eventValue(event, 'repeat'),
      data: eventValue(event, 'data'),
      input_type: eventValue(event, 'inputType'),
      is_composing: eventValue(event, 'isComposing'),
      active_element: elementIdentity(document.activeElement),
      event_target: elementIdentity(event.target),
    };
  }

  function createTextSelectionSnapshotter(target, { contextRadius = 32 } = {}) {
    if (!(target instanceof Node)) {
      throw new TypeError('Text selection snapshot target must be a DOM node.');
    }

    const requestedRadius = Number(contextRadius);
    const radius = Number.isFinite(requestedRadius)
      ? Math.min(Math.max(Math.trunc(requestedRadius), 0), maximumContextRadius)
      : 32;
    let observedTarget = target;
    let nodeOffsets = new WeakMap();
    let textRuns = [];
    let textLength = 0;
    let dirty = true;
    let stopped = false;

    const observer = new MutationObserver(() => {
      dirty = true;
    });
    observer.observe(observedTarget, {
      childList: true,
      characterData: true,
      subtree: true,
    });

    function rebuildIndex() {
      nodeOffsets = new WeakMap();
      textRuns = [];
      textLength = 0;

      function visit(node) {
        const start = textLength;
        const isText = node.nodeType === Node.TEXT_NODE ||
          node.nodeType === Node.CDATA_SECTION_NODE;
        if (isText) {
          const text = node.nodeValue ?? '';
          if (text.length > 0) {
            textRuns.push({ start, end: start + text.length, text });
            textLength += text.length;
          }
        } else {
          for (const child of node.childNodes) {
            visit(child);
          }
        }
        nodeOffsets.set(node, { start, end: textLength });
      }

      visit(observedTarget);
      dirty = false;
    }

    function refreshIndex() {
      if (observer.takeRecords().length > 0) {
        dirty = true;
      }
      if (dirty) {
        rebuildIndex();
      }
    }

    function boundaryOffset(container, offset) {
      const entry = nodeOffsets.get(container);
      if (!entry || !Number.isInteger(offset) || offset < 0) {
        return null;
      }

      const isText = container.nodeType === Node.TEXT_NODE ||
        container.nodeType === Node.CDATA_SECTION_NODE;
      if (isText) {
        const length = (container.nodeValue ?? '').length;
        return offset <= length ? entry.start + offset : null;
      }

      if (offset > container.childNodes.length) {
        return null;
      }
      if (offset === container.childNodes.length) {
        return entry.end;
      }
      return nodeOffsets.get(container.childNodes[offset])?.start ?? null;
    }

    function firstRunEndingAfter(offset) {
      let lowerBound = 0;
      let upperBound = textRuns.length;
      while (lowerBound < upperBound) {
        const middle = Math.floor((lowerBound + upperBound) / 2);
        if (textRuns[middle].end <= offset) {
          lowerBound = middle + 1;
        } else {
          upperBound = middle;
        }
      }
      return lowerBound;
    }

    function textSlice(start, end) {
      if (start >= end) {
        return '';
      }

      let result = '';
      for (let index = firstRunEndingAfter(start); index < textRuns.length; index += 1) {
        const run = textRuns[index];
        if (run.start >= end) {
          break;
        }
        const localStart = Math.max(start, run.start) - run.start;
        const localEnd = Math.min(end, run.end) - run.start;
        result += run.text.slice(localStart, localEnd);
      }
      return result;
    }

    function snapshot() {
      if (stopped) {
        throw new Error('Text selection snapshotter has been stopped.');
      }
      refreshIndex();

      const selection = window.getSelection();
      const range = selection?.rangeCount ? selection.getRangeAt(0) : null;
      const state = {
        editor_text_length: textLength,
        selection_start: range ? boundaryOffset(range.startContainer, range.startOffset) : null,
        selection_end: range ? boundaryOffset(range.endContainer, range.endOffset) : null,
        selection_anchor: selection ? boundaryOffset(selection.anchorNode, selection.anchorOffset) : null,
        selection_focus: selection ? boundaryOffset(selection.focusNode, selection.focusOffset) : null,
        caret_context: null,
      };

      if (state.selection_focus != null) {
        const beforeStart = Math.max(0, state.selection_focus - radius);
        const afterEnd = Math.min(textLength, state.selection_focus + radius);
        state.caret_context = {
          before: textSlice(beforeStart, state.selection_focus),
          after: textSlice(state.selection_focus, afterEnd),
          before_truncated: beforeStart > 0,
          after_truncated: afterEnd < textLength,
        };
      }
      return state;
    }

    function stop() {
      if (stopped) {
        return;
      }
      stopped = true;
      observer.disconnect();
      observer.takeRecords();
      observedTarget = null;
      nodeOffsets = new WeakMap();
      textRuns = [];
      textLength = 0;
    }

    return { snapshot, stop };
  }

  function create({ eventTypes, snapshot, afterRecord }) {
    const events = [];
    const listeners = [];
    let sequence = 0;
    let started = false;

    function record(event) {
      events.push({
        sequence: ++sequence,
        ...serializeEvent(event),
        ...(snapshot?.(event) ?? {}),
      });
      afterRecord?.(event);
    }

    function start() {
      if (started) {
        return;
      }
      started = true;
      for (const type of eventTypes) {
        document.addEventListener(type, record, { capture: true });
        listeners.push([type, record]);
      }
    }

    function stop() {
      for (const [type, listener] of listeners.splice(0)) {
        document.removeEventListener(type, listener, { capture: true });
      }
      started = false;
    }

    return { events, start, stop };
  }

  window.__hisleDOMEventRecorder = {
    create,
    createTextSelectionSnapshotter,
    elementIdentity,
  };
}
