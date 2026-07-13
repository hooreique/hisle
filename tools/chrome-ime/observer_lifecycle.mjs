/**
 * A small async cleanup stack for browser observers.
 *
 * Cleanup runs in reverse registration order. Disposal never rejects: callers
 * receive every cleanup failure with the label used at registration time.
 */
export class AsyncCleanupStack {
  #entries = [];
  #pendingAcquisitions = new Set();
  #disposeRequested = false;
  #disposePromise = null;

  get disposeRequested() {
    return this.#disposeRequested;
  }

  defer(label, cleanup) {
    validateCleanup(label, cleanup);
    if (this.#disposeRequested) {
      throw new Error(`Cannot register cleanup after disposal was requested: ${label}`);
    }

    this.#entries.push({ label, cleanup });
  }

  /**
   * Acquire a resource and register its cleanup as one operation.
   *
   * If disposal is requested while acquisition is pending, dispose() waits for
   * the acquisition to settle. A resource that arrives late is still registered
   * and closed before disposal completes.
   */
  acquire(label, acquireResource, cleanupResource) {
    validateCleanup(label, cleanupResource);
    if (typeof acquireResource !== 'function') {
      throw new TypeError('acquireResource must be a function');
    }
    if (this.#disposeRequested) {
      return Promise.reject(
        new Error(`Cannot acquire a resource after disposal was requested: ${label}`),
      );
    }

    const acquisition = Promise.resolve()
      .then(acquireResource)
      .then((resource) => {
        this.#entries.push({
          label,
          cleanup: () => cleanupResource(resource),
        });
        return resource;
      });

    this.#pendingAcquisitions.add(acquisition);
    acquisition.then(
      () => this.#pendingAcquisitions.delete(acquisition),
      () => this.#pendingAcquisitions.delete(acquisition),
    );
    return acquisition;
  }

  dispose() {
    if (this.#disposePromise) {
      return this.#disposePromise;
    }

    this.#disposeRequested = true;
    this.#disposePromise = this.#disposeEntries();
    return this.#disposePromise;
  }

  async #disposeEntries() {
    const errors = [];

    // acquire() is rejected after disposeRequested is set, so this snapshot
    // contains every acquisition that can still register a cleanup entry.
    await Promise.allSettled([...this.#pendingAcquisitions]);

    while (this.#entries.length > 0) {
      const { label, cleanup } = this.#entries.pop();
      try {
        await cleanup();
      } catch (error) {
        errors.push({ label, error });
      }
    }

    return { errors };
  }
}

export const ObserverLifecycle = AsyncCleanupStack;

export async function closeHttpServer(server) {
  if (!server || typeof server.close !== 'function' || server.listening === false) {
    return;
  }

  await new Promise((resolve, reject) => {
    let settled = false;
    const finish = (error) => {
      if (settled) {
        return;
      }
      settled = true;
      if (isServerNotRunning(error)) {
        resolve();
      } else if (error) {
        reject(error);
      } else {
        resolve();
      }
    };

    try {
      const result = server.close(finish);
      if (result && typeof result.then === 'function') {
        result.then(() => finish(), finish);
      } else if (server.close.length === 0) {
        // Support synchronous, callback-free test doubles.
        finish();
      }
    } catch (error) {
      finish(error);
    }
  });
}

export async function closeFirefoxSession({ driver, service } = {}) {
  const errors = [];

  if (driver && typeof driver.quit === 'function') {
    try {
      await driver.quit();
    } catch (error) {
      errors.push({ label: 'firefox-driver', error });
    }
  }

  if (service && typeof service.kill === 'function') {
    try {
      await service.kill();
    } catch (error) {
      errors.push({ label: 'geckodriver-service', error });
    }
  }

  throwIfCleanupFailed('Failed to close the Firefox session', errors);
}

/**
 * Close a Chromium connection created by connectOverCDP().
 *
 * Playwright browser.close() only disconnects a connected Browser. An owned
 * normal-Chrome process therefore receives the CDP Browser.close command first.
 * Reused Chrome is externally owned and is only disconnected.
 */
export async function closeConnectedChromium({
  browser,
  owned = false,
  ensureOwnedProcessStopped,
} = {}) {
  const errors = [];

  if (owned && browser) {
    try {
      const session = await browser.newBrowserCDPSession();
      await session.send('Browser.close');
    } catch (error) {
      errors.push({ label: 'chromium-browser-close', error });
    }
  }

  if (browser && typeof browser.close === 'function') {
    try {
      await browser.close();
    } catch (error) {
      errors.push({ label: 'chromium-disconnect', error });
    }
  }

  if (owned && typeof ensureOwnedProcessStopped === 'function') {
    try {
      await ensureOwnedProcessStopped();
    } catch (error) {
      errors.push({ label: 'chromium-process', error });
    }
  }

  throwIfCleanupFailed('Failed to close the connected Chromium browser', errors);
}

function validateCleanup(label, cleanup) {
  if (typeof label !== 'string' || label.length === 0) {
    throw new TypeError('cleanup label must be a non-empty string');
  }
  if (typeof cleanup !== 'function') {
    throw new TypeError('cleanup must be a function');
  }
}

function isServerNotRunning(error) {
  return error?.code === 'ERR_SERVER_NOT_RUNNING';
}

function throwIfCleanupFailed(message, cleanupErrors) {
  if (cleanupErrors.length === 0) {
    return;
  }

  const aggregate = new AggregateError(
    cleanupErrors.map(({ error }) => error),
    message,
  );
  aggregate.cleanupErrors = cleanupErrors;
  throw aggregate;
}
