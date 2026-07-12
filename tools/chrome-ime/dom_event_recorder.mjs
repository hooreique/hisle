export function installDOMEventRecorder() {
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
    elementIdentity,
  };
}
